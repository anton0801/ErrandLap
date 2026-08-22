//
//  Planner.swift
//  ErrandRun
//
//  The feasibility engine. It knows opening hours, lunch breaks, last entry,
//  travel and buffers — and it never pretends to know the queue.
//

import Foundation

// MARK: - Data lookups

extension AppData {
    func place(_ id: UUID?) -> Place? {
        guard let id else { return nil }
        return places.first { $0.id == id }
    }

    func errand(_ id: UUID?) -> Errand? {
        guard let id else { return nil }
        return errands.first { $0.id == id }
    }

    func window(_ id: UUID?) -> FreeWindow? {
        guard let id else { return nil }
        return windows.first { $0.id == id }
    }

    func run(_ id: UUID?) -> Run? {
        guard let id else { return nil }
        return runs.first { $0.id == id }
    }

    func name(for endpoint: Endpoint) -> String {
        switch endpoint {
        case .home: return "home"
        case .work: return "work"
        case .place(let id): return place(id)?.name ?? "the place"
        case .custom(let label): return label.isEmpty ? "the meeting point" : label
        }
    }

    func coordinate(for endpoint: Endpoint) -> GeoPoint? {
        switch endpoint {
        case .home: return settings.homeCoordinate
        case .work: return settings.workCoordinate
        case .place(let id): return place(id)?.coordinate
        case .custom: return nil
        }
    }

    func address(for endpoint: Endpoint) -> String {
        switch endpoint {
        case .home: return settings.homeAddress
        case .work: return settings.workAddress
        case .place(let id): return place(id)?.address ?? ""
        case .custom: return ""
        }
    }

    static func travelKey(_ from: Endpoint, _ to: Endpoint, _ mode: TravelMode) -> String {
        "\(from.key)>\(to.key)|\(mode.rawValue)"
    }
}

// MARK: - Results

struct TravelLookup: Hashable {
    var minutes: Int?
    var source: TravelSource?

    var known: Bool { minutes != nil }
}

struct QueueKnowledge: Hashable {
    /// Minutes added on top of the errand's own duration.
    var allowance: Int
    /// Total measured time inside, averaged.
    var averageInside: Int
    var visits: Int
    var learned: Bool
    var userEstimate: Int
    var recentActuals: [Int]

    var sentence: String {
        if learned {
            return "Your own average here: \(averageInside) minutes over \(visits) visit\(visits == 1 ? "" : "s")."
        }
        return "No data yet. Your estimate: \(userEstimate) minutes. The app will learn the real number."
    }
}

struct StopPlan: Identifiable, Hashable {
    var id: UUID
    var errand: Errand
    var place: Place
    var travel: Int
    var travelSource: TravelSource?
    var depart: Int
    var arrive: Int
    var wait: Int
    var startInside: Int
    var inside: Int
    var queue: Int
    var leave: Int
    var close: Int?
    var lastEntry: Int?
    var tight: Bool
    var line: String
}

struct SimFailure: Hashable {
    var errandID: UUID
    var reason: String
}

struct Simulation {
    var stops: [StopPlan] = []
    var failure: SimFailure?
    var endArrival: Int = 0
    var returnTravel: Int = 0
    var returnKnown: Bool = true

    var feasible: Bool { failure == nil }
}

struct MissedErrand: Identifiable, Hashable {
    var id: UUID
    var errand: Errand
    var place: Place?
    var reason: String
    var suggestion: String?
    var suggestedInstanceID: String?
}

struct RoutePlan {
    var instance: WindowInstance
    var stops: [StopPlan] = []
    var didNotFit: [MissedErrand] = []
    var noPlace: [Errand] = []
    var endArrival: Int = 0
    var returnTravel: Int = 0
    var lines: [String] = []

    var windowMinutes: Int { instance.minutes }
    var usedMinutes: Int { max(0, endArrival - instance.start) }
    var isEmpty: Bool { stops.isEmpty }

    var earliestClosing: (place: Place, close: Int)? {
        let candidates = stops.compactMap { stop -> (Place, Int)? in
            guard let close = stop.close else { return nil }
            return (stop.place, close)
        }
        guard let best = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        return (best.0, best.1)
    }
}

struct SimContext {
    var day: Date
    var startMinutes: Int
    var endMinutes: Int
    var from: Endpoint
    var to: Endpoint
    var mode: TravelMode
}

// MARK: - Planner

struct Planner {
    var data: AppData

    private var buffer: Int { data.settings.buffer }

    // MARK: Travel

    func travel(_ from: Endpoint, _ to: Endpoint, mode: TravelMode) -> TravelLookup {
        if from == to { return TravelLookup(minutes: 0, source: .map) }
        if let entry = data.travel[AppData.travelKey(from, to, mode)] {
            return TravelLookup(minutes: entry.minutes, source: entry.source)
        }
        if let entry = data.travel[AppData.travelKey(to, from, mode)] {
            return TravelLookup(minutes: entry.minutes, source: entry.source)
        }
        if let estimate = distanceEstimate(from, to, mode: mode) {
            return TravelLookup(minutes: estimate, source: .distance)
        }
        return TravelLookup(minutes: nil, source: nil)
    }

    /// Straight line, inflated for real streets. Only used when nothing better exists.
    func distanceEstimate(_ from: Endpoint, _ to: Endpoint, mode: TravelMode) -> Int? {
        guard let a = data.coordinate(for: from), let b = data.coordinate(for: to) else { return nil }
        let kilometres = Planner.distanceKm(a, b) * 1.35
        let speed = mode.speed(pace: data.settings.walkingPace)
        guard speed > 0 else { return nil }
        return max(1, Int((kilometres / speed * 60).rounded(.up)))
    }

    static func distanceKm(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let earth = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * earth * asin(min(1, sqrt(h)))
    }

    // MARK: Queue knowledge

    func queue(for placeID: UUID) -> QueueKnowledge {
        let place = data.place(placeID)
        let estimate = place?.queueEstimate ?? 10
        let logs = data.visits
            .filter { $0.placeID == placeID }
            .sorted { $0.date > $1.date }
        guard data.settings.learnFromVisits, logs.count >= 2 else {
            return QueueKnowledge(allowance: estimate,
                                  averageInside: logs.first?.actual ?? estimate,
                                  visits: logs.count,
                                  learned: false,
                                  userEstimate: estimate,
                                  recentActuals: logs.prefix(3).map(\.actual))
        }
        let recent = Array(logs.prefix(5))
        let averageInside = recent.map(\.actual).reduce(0, +) / recent.count
        let overheads = recent.map { max(0, $0.actual - $0.taskMinutes) }
        let allowance = overheads.reduce(0, +) / max(1, overheads.count)
        return QueueKnowledge(allowance: allowance,
                              averageInside: averageInside,
                              visits: logs.count,
                              learned: true,
                              userEstimate: estimate,
                              recentActuals: recent.prefix(3).map(\.actual))
    }

    // MARK: Window instances

    /// Windows that still have time left in them. A window already running starts from the clock.
    func instances(from day: Date = Date(), days: Int = 21) -> [WindowInstance] {
        let nowMinutes = ERTime.minutes(from: day)
        var result: [WindowInstance] = []
        for offset in 0..<days {
            let date = ERTime.adding(days: offset, to: ERTime.startOfDay(day))
            for window in data.windows where window.occurs(on: date) {
                var instance = WindowInstance(window: window, day: date)
                if offset == 0, ERTime.isSameDay(date, day) {
                    if window.end <= nowMinutes { continue }
                    if window.start < nowMinutes { instance.startFrom = nowMinutes }
                }
                result.append(instance)
            }
        }
        return result.sorted { lhs, rhs in
            if ERTime.isSameDay(lhs.day, rhs.day) { return lhs.start < rhs.start }
            return lhs.day < rhs.day
        }
    }

    func todayInstances(now: Date = Date()) -> [WindowInstance] {
        instances(from: now, days: 1)
    }

    /// The window we are inside right now, otherwise the next one still to come today.
    func currentInstance(now: Date = Date()) -> WindowInstance? {
        todayInstances(now: now).first
    }

    func nextInstance(after now: Date = Date()) -> WindowInstance? {
        instances(from: now, days: 21).first
    }

    // MARK: Dependencies

    func isBlocked(_ errand: Errand) -> Bool {
        guard let dependency = errand.dependsOn, let other = data.errand(dependency) else { return false }
        return other.state != .done
    }

    func blockingReason(_ errand: Errand) -> String? {
        guard let dependency = errand.dependsOn, let other = data.errand(dependency), other.state != .done else { return nil }
        return "Blocked. You need \(other.title.lowercased()) first."
    }

    /// A recurring errand is not due until its window of tolerance opens.
    func isDue(_ errand: Errand, on day: Date) -> Bool {
        guard let recurrence = errand.recurrence else { return true }
        let earliest = ERTime.adding(days: -recurrence.flexibleByDays, to: recurrence.nextDue)
        return ERTime.startOfDay(day) >= ERTime.startOfDay(earliest)
    }

    // MARK: Simulation

    func simulate(_ order: [UUID], in context: SimContext) -> Simulation {
        var result = Simulation()
        var time = context.startMinutes
        var current = context.from

        for errandID in order {
            guard let errand = data.errand(errandID) else { continue }
            guard let placeID = errand.placeID, let place = data.place(placeID) else {
                result.failure = SimFailure(errandID: errandID, reason: "No place set for \(errand.title).")
                return result
            }
            let hours = place.hours(on: context.day)
            guard hours.isOpen else {
                result.failure = SimFailure(
                    errandID: errandID,
                    reason: "\(place.name) is closed on \(ERTime.weekdayName(ERTime.weekday(context.day)))."
                )
                return result
            }
            let lookup = travel(current, place.endpoint, mode: context.mode)
            guard let travelMinutes = lookup.minutes else {
                result.failure = SimFailure(
                    errandID: errandID,
                    reason: "No travel time yet between \(data.name(for: current)) and \(place.name)."
                )
                return result
            }

            let depart = time
            var arrive = time + travelMinutes + buffer + place.parking.extraMinutes
            var wait = 0
            if arrive < hours.open {
                wait += hours.open - arrive
                arrive = hours.open
            }
            if hours.hasLunch, arrive >= hours.lunchStart, arrive < hours.lunchEnd {
                wait += hours.lunchEnd - arrive
                arrive = hours.lunchEnd
            }

            let knowledge = queue(for: place.id)
            let inside = errand.duration + knowledge.allowance
            var startInside = arrive
            if hours.hasLunch, startInside < hours.lunchStart, startInside + inside > hours.lunchStart {
                wait += hours.lunchEnd - startInside
                startInside = hours.lunchEnd
            }

            if hours.lastEntryOffset > 0, startInside > hours.lastEntry {
                result.failure = SimFailure(
                    errandID: errandID,
                    reason: "You would get to \(place.name) at \(ERTime.time(startInside)). Last entry is \(ERTime.time(hours.lastEntry))."
                )
                return result
            }

            let leave = startInside + inside
            if leave > hours.close {
                result.failure = SimFailure(
                    errandID: errandID,
                    reason: "You would start at \(ERTime.time(startInside)) and need \(inside) minutes. \(place.name) closes at \(ERTime.time(hours.close))."
                )
                return result
            }

            let tight = (hours.lastEntryOffset > 0 && hours.lastEntry - startInside <= 10) || (hours.close - leave <= 10)
            let line = Planner.line(place: place,
                                    travel: travelMinutes,
                                    mode: context.mode,
                                    inside: inside,
                                    hours: hours,
                                    arrive: startInside,
                                    tight: tight)

            result.stops.append(StopPlan(
                id: errand.id,
                errand: errand,
                place: place,
                travel: travelMinutes,
                travelSource: lookup.source,
                depart: depart,
                arrive: arrive,
                wait: wait,
                startInside: startInside,
                inside: inside,
                queue: knowledge.allowance,
                leave: leave,
                close: hours.close,
                lastEntry: hours.lastEntryOffset > 0 ? hours.lastEntry : nil,
                tight: tight,
                line: line
            ))

            time = leave
            current = place.endpoint
        }

        let back = travel(current, context.to, mode: context.mode)
        result.returnTravel = back.minutes ?? 0
        result.returnKnown = back.known || current == context.to
        result.endArrival = time + result.returnTravel

        if result.endArrival > context.endMinutes, let last = order.last {
            let errand = data.errand(last)
            let placeName = data.place(errand?.placeID)?.name ?? errand?.title ?? "the last stop"
            result.failure = SimFailure(
                errandID: last,
                reason: "You would leave \(placeName) at \(ERTime.time(time)) and still need \(result.returnTravel) minutes to reach \(data.name(for: context.to)) by \(ERTime.time(context.endMinutes))."
            )
        }
        return result
    }

    static func line(place: Place, travel: Int, mode: TravelMode, inside: Int, hours: DayHours, arrive: Int, tight: Bool, errandLabel: String? = nil) -> String {
        let subject = errandLabel.map { "\(place.name), \($0.lowercased())" } ?? place.name
        var text = "\(subject): \(travel) minutes \(mode.noun), \(inside) minutes inside, closes at \(ERTime.time(hours.close))"
        if hours.lastEntryOffset > 0 {
            text += " with last entry \(ERTime.time(hours.lastEntry))"
        }
        text += "."
        if tight {
            text += " You arrive \(ERTime.time(arrive)). Tight but fits."
        } else {
            text += " Fits."
        }
        return text
    }

    func context(for instance: WindowInstance) -> SimContext {
        SimContext(day: instance.day,
                   startMinutes: instance.start,
                   endMinutes: instance.end,
                   from: instance.window.from,
                   to: instance.window.to,
                   mode: instance.window.travelMode)
    }

    // MARK: Candidates and planning

    func candidates(for instance: WindowInstance) -> [Errand] {
        data.errands.filter { errand in
            errand.state == .open
                && errand.placeID != nil
                && data.place(errand.placeID) != nil
                && !isBlocked(errand)
                && isDue(errand, on: instance.day)
                && errand.delegation?.status != .doneByThem
        }
    }

    /// Earliest closing first — that is what decides the order, not importance.
    func sorted(_ errands: [Errand], on day: Date) -> [Errand] {
        errands.sorted { lhs, rhs in
            let lhsClose = closingKey(lhs, on: day)
            let rhsClose = closingKey(rhs, on: day)
            if lhsClose != rhsClose { return lhsClose < rhsClose }
            let lhsDeadline = lhs.deadline?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
            let rhsDeadline = rhs.deadline?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
            if lhsDeadline != rhsDeadline { return lhsDeadline < rhsDeadline }
            if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
            return lhs.duration < rhs.duration
        }
    }

    private func closingKey(_ errand: Errand, on day: Date) -> Int {
        guard let place = data.place(errand.placeID) else { return 24 * 60 }
        let hours = place.hours(on: day)
        guard hours.isOpen else { return 24 * 60 + 1 }
        return hours.lastEntryOffset > 0 ? hours.lastEntry : hours.close
    }

    func plan(for instance: WindowInstance, restrictedTo ids: [UUID]? = nil, lookAheadDays: Int = 21) -> RoutePlan {
        var plan = RoutePlan(instance: instance)
        let context = context(for: instance)

        var pool = candidates(for: instance)
        if let ids {
            pool = ids.compactMap { id in pool.first { $0.id == id } }
        } else {
            pool = sorted(pool, on: instance.day)
        }

        plan.noPlace = data.errands.filter { $0.state == .open && $0.placeID == nil && !isBlocked($0) }

        var accepted: [UUID] = []
        var lastGood = Simulation()

        for errand in pool {
            let trial = simulate(accepted + [errand.id], in: context)
            if trial.feasible {
                accepted.append(errand.id)
                lastGood = trial
            } else {
                let reason = trial.failure?.reason ?? "It does not fit this window."
                let suggestion = nextFittingInstance(for: errand, after: instance, days: lookAheadDays)
                plan.didNotFit.append(MissedErrand(
                    id: errand.id,
                    errand: errand,
                    place: data.place(errand.placeID),
                    reason: reason,
                    suggestion: suggestion.map { suggestionText(for: errand, instance: $0) },
                    suggestedInstanceID: suggestion?.id
                ))
            }
        }

        plan.stops = lastGood.stops
        plan.endArrival = accepted.isEmpty ? instance.start : lastGood.endArrival
        plan.returnTravel = lastGood.returnTravel
        plan.lines = describe(plan: plan)
        return plan
    }

    /// The user moved something by hand. Simulate exactly what they asked for and
    /// report the consequence without arguing.
    func plan(order: [UUID], for instance: WindowInstance) -> (plan: RoutePlan, failure: SimFailure?) {
        var result = RoutePlan(instance: instance)
        let simulation = simulate(order, in: context(for: instance))
        result.stops = simulation.stops
        result.endArrival = simulation.stops.isEmpty ? instance.start : simulation.endArrival
        result.returnTravel = simulation.returnTravel
        result.noPlace = data.errands.filter { $0.state == .open && $0.placeID == nil && !isBlocked($0) }

        let placedIDs = Set(simulation.stops.map(\.id))
        let leftovers = order.filter { !placedIDs.contains($0) }
        for id in leftovers {
            guard let errand = data.errand(id) else { continue }
            let reason = simulation.failure?.errandID == id
                ? (simulation.failure?.reason ?? "It does not fit this window.")
                : "It comes after a stop that does not fit."
            let suggestion = nextFittingInstance(for: errand, after: instance)
            result.didNotFit.append(MissedErrand(id: id,
                                                 errand: errand,
                                                 place: data.place(errand.placeID),
                                                 reason: reason,
                                                 suggestion: suggestion.map { suggestionText(for: errand, instance: $0) },
                                                 suggestedInstanceID: suggestion?.id))
        }
        result.lines = describe(plan: result)
        return (result, simulation.failure)
    }

    func describe(plan: RoutePlan) -> [String] {
        var lines: [String] = []
        let instance = plan.instance
        lines.append("Window: \(ERTime.time(instance.start)) to \(ERTime.time(instance.end)). \(ERTime.minutesWord(instance.minutes)).")
        lines.append("Leaving \(data.name(for: instance.window.from)) at \(ERTime.time(instance.start)).")
        let repeatedPlaces = Dictionary(grouping: plan.stops, by: { $0.place.id })
            .filter { $0.value.count > 1 }
            .keys
        for stop in plan.stops {
            if repeatedPlaces.contains(stop.place.id) {
                let hours = stop.place.hours(on: instance.day)
                lines.append(Planner.line(place: stop.place,
                                          travel: stop.travel,
                                          mode: instance.window.travelMode,
                                          inside: stop.inside,
                                          hours: hours,
                                          arrive: stop.startInside,
                                          tight: stop.tight,
                                          errandLabel: stop.errand.title))
            } else {
                lines.append(stop.line)
            }
        }
        for missed in plan.didNotFit {
            // Two errands at one place must not read as the same line twice.
            let name = missed.place.map { "\($0.name), \(missed.errand.title.lowercased())" } ?? missed.errand.title
            lines.append("\(name): \(missed.reason) Does not fit.")
        }
        if !plan.stops.isEmpty {
            lines.append("Back at \(data.name(for: instance.window.to)) by \(ERTime.time(plan.endArrival)).")
            lines.append("Total with buffers: \(plan.usedMinutes) of \(plan.windowMinutes) minutes.")
        }
        return lines
    }

    /// Why this order — the app explaining that hours beat priorities.
    func orderExplanation(for plan: RoutePlan) -> [String] {
        guard !plan.stops.isEmpty else { return [] }
        var lines: [String] = []
        for stop in plan.stops {
            let hours = stop.place.hours(on: plan.instance.day)
            if hours.lastEntryOffset > 0 {
                lines.append("\(stop.place.name) stops letting people in at \(ERTime.time(hours.lastEntry)).")
            } else {
                lines.append("\(stop.place.name) closes at \(ERTime.time(hours.close)).")
            }
        }
        lines.append("Earliest closing goes first, even when it matters less. Importance does not move a door that is already locked.")
        return lines
    }

    // MARK: Looking ahead

    func nextFittingInstance(for errand: Errand, after instance: WindowInstance?, days: Int = 21) -> WindowInstance? {
        let all = instances(from: Date(), days: days)
        for candidate in all {
            if let instance, candidate.id == instance.id { continue }
            if let instance, candidate.day < instance.day { continue }
            guard isDue(errand, on: candidate.day) else { continue }
            let trial = simulate([errand.id], in: context(for: candidate))
            if trial.feasible { return candidate }
        }
        return nil
    }

    func suggestionText(for errand: Errand, instance: WindowInstance) -> String {
        guard let place = data.place(errand.placeID) else {
            return "Your window \(ERTime.dayPhrase(instance.day)) at \(instance.timeText) works."
        }
        let hours = place.hours(on: instance.day)
        return "\(place.name) is open \(hours.shortText) \(ERTime.dayPhrase(instance.day)) — your \(instance.timeText) window works."
    }

    /// How many windows are left before a deadline. The only honest measure of urgency.
    func windowsBefore(deadline: Date, for errand: Errand) -> [WindowInstance] {
        let horizon = max(1, ERTime.daysBetween(Date(), deadline) + 1)
        return instances(from: Date(), days: min(horizon, 120)).filter { candidate in
            guard ERTime.startOfDay(candidate.day) <= ERTime.startOfDay(deadline) else { return false }
            return simulate([errand.id], in: context(for: candidate)).feasible
        }
    }

    // MARK: Sections

    func section(for errand: Errand, plannedIDs: Set<UUID>) -> ErrandSection {
        switch errand.state {
        case .done: return .done
        case .dropped: return .dropped
        case .open: break
        }
        if isBlocked(errand) { return .blocked }
        if plannedIDs.contains(errand.id) { return .scheduled }
        if errand.placeID != nil, data.place(errand.placeID) != nil,
           nextFittingInstance(for: errand, after: nil, days: 14) != nil {
            return .waiting
        }
        return .open
    }
}
