//
//  AppStore.swift
//  ErrandRun
//
//  One observable store, one JSON file on disk. No account, no server.
//

import Foundation
import SwiftUI

struct NextStep: Hashable {
    var title: String
    var detail: String
    var actionTitle: String?
    var action: NextStepAction?
}

enum NextStepAction: Hashable {
    case addErrand
    case addPlace
    case addWindow
    case assignPlaces
    case fixTravelTime
    case openBuilder
    case resumeRun
}

struct Derived {
    var sections: [UUID: ErrandSection] = [:]
    var currentInstance: WindowInstance?
    var nextInstance: WindowInstance?
    var todayPlan: RoutePlan?
    var nextStep: NextStep?
    var doneThisWeek: Int = 0
    var waitingCount: Int = 0
}

final class AppStore: ObservableObject {
    @Published var data: AppData {
        didSet { scheduleSave() }
    }

    @Published private(set) var derived = Derived()
    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?

    private var saveWorkItem: DispatchWorkItem?
    private let fileURL: URL
    private let photosURL: URL

    /// False only while server changes are being written in, so they are not
    /// mistaken for local edits and pushed straight back.
    private var tracksChanges = true

    /// Set by the sync engine; called after any local edit.
    var onLocalChange: (() -> Void)?

    // MARK: Init

    init(inMemory: Bool = false) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = support.appendingPathComponent("ErrandRun", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("errandrun.json")
        photosURL = folder.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)

        if inMemory {
            data = AppData()
            isLoading = false
            recompute()
            return
        }

        data = AppData()
        load()
    }

    var planner: Planner { Planner(data: data) }

    // MARK: Persistence

    func load() {
        isLoading = true
        loadError = nil
        defer {
            isLoading = false
            recompute()
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            data = AppData()
            return
        }
        do {
            let raw = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            data = try decoder.decode(AppData.self, from: raw)
        } catch {
            loadError = "The saved file could not be read. Nothing was deleted — it is still on disk."
            data = AppData()
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    func saveNow() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let raw = try encoder.encode(data)
            try raw.write(to: fileURL, options: .atomic)
        } catch {
            loadError = "Could not write to disk: \(error.localizedDescription)"
        }
    }

    var storageURL: URL { fileURL }

    // MARK: Mutation

    /// Every local edit goes through here, so change tracking cannot be forgotten
    /// at a call site: the difference before and after the block is what gets synced.
    func mutate(_ block: (inout AppData) -> Void) {
        let before = tracksChanges ? ChangeTracker.snapshot(of: data) : nil
        block(&data)
        if let before {
            ChangeTracker.apply(before: before, to: &data, at: Date())
        }
        recompute()
        Notifications.shared.reschedule(store: self)
        if tracksChanges {
            onLocalChange?()
        }
    }

    /// Applies what came back from the server without marking any of it as a local edit.
    func applyRemote(_ block: (inout AppData) -> Void) {
        tracksChanges = false
        block(&data)
        tracksChanges = true
        recompute()
    }

    // MARK: Derived state

    func recompute(now: Date = Date()) {
        let planner = self.planner
        var result = Derived()

        result.currentInstance = planner.currentInstance(now: now)
        result.nextInstance = planner.nextInstance(after: now)

        let instance = result.currentInstance ?? result.nextInstance
        if let instance {
            result.todayPlan = planner.plan(for: instance)
        }

        var planned = Set(result.todayPlan?.stops.map(\.id) ?? [])
        for run in data.runs where run.state == .planned || run.state == .running {
            planned.formUnion(run.stops.map(\.errandID))
        }

        var sections: [UUID: ErrandSection] = [:]
        for errand in data.errands {
            sections[errand.id] = planner.section(for: errand, plannedIDs: planned)
        }
        result.sections = sections
        result.waitingCount = sections.values.filter { $0 == .waiting }.count

        let weekAgo = ERTime.adding(days: -7, to: now)
        result.doneThisWeek = data.errands.filter { errand in
            guard let doneAt = errand.doneAt, errand.state == .done else { return false }
            return doneAt >= weekAgo
        }.count

        result.nextStep = nextStep(planner: planner, derived: result, now: now)
        derived = result
    }

    private func nextStep(planner: Planner, derived: Derived, now: Date) -> NextStep? {
        if let activeID = data.activeRunID, let run = data.run(activeID), run.state == .running {
            return NextStep(title: "Run in Progress",
                            detail: "You left \(data.name(for: run.from)) at \(ERTime.time(run.start)). \(run.doneCount) of \(run.stops.count) done.",
                            actionTitle: "Resume",
                            action: .resumeRun)
        }

        let openErrands = data.errands.filter { $0.state == .open }
        if openErrands.isEmpty {
            return nil
        }

        if data.windows.isEmpty {
            return NextStep(title: "No Free Windows Yet",
                            detail: "Tell the app when you are actually free — a lunch break, Saturday morning — and it will work out what fits.",
                            actionTitle: "Add a Window",
                            action: .addWindow)
        }

        let withoutPlace = openErrands.filter { $0.placeID == nil }
        if withoutPlace.count > 1 {
            return NextStep(title: "\(Self.spell(withoutPlace.count)) Errands Have No Place",
                            detail: "Without a place there are no opening hours and no travel time, so they cannot be planned.",
                            actionTitle: "Assign Places",
                            action: .assignPlaces)
        }
        if let single = withoutPlace.first {
            return NextStep(title: "\(single.title) Has No Place",
                            detail: "Without a place there are no opening hours and no travel time, so it cannot be planned.",
                            actionTitle: "Assign a Place",
                            action: .assignPlaces)
        }

        if let plan = derived.todayPlan {
            if let missingTravel = plan.didNotFit.first(where: { $0.reason.hasPrefix("No travel time") }) {
                return NextStep(title: "Travel Time Missing",
                                detail: missingTravel.reason + " Add it by hand or recalculate it from the map.",
                                actionTitle: "Fix Travel Time",
                                action: .fixTravelTime)
            }
            if plan.stops.isEmpty, let shortest = openErrands.map(\.duration).min(), plan.instance.minutes < shortest {
                return NextStep(title: "Only \(plan.instance.minutes) Minutes Free Today",
                                detail: "Your shortest errand needs \(shortest) minutes inside, before travel. Nothing fits this window.",
                                actionTitle: nil,
                                action: nil)
            }
            if let missed = plan.didNotFit.first(where: { $0.reason.contains("closes at") || $0.reason.contains("Last entry") }) {
                let name = missed.place?.name ?? missed.errand.title
                return NextStep(title: "\(name) Closes Before You Arrive",
                                detail: missed.reason,
                                actionTitle: missed.suggestion == nil ? nil : "See the Route",
                                action: missed.suggestion == nil ? nil : .openBuilder)
            }
            if !plan.stops.isEmpty {
                let first = plan.stops[0]
                return NextStep(title: "Leave By \(ERTime.time(plan.instance.start))",
                                detail: "First stop \(first.place.name), \(first.travel) minutes \(plan.instance.window.travelMode.noun). You would be inside at \(ERTime.time(first.startInside)).",
                                actionTitle: "Open the Route",
                                action: .openBuilder)
            }
        }

        if derived.currentInstance == nil, let next = derived.nextInstance {
            return NextStep(title: "Waiting for a Window",
                            detail: "Your next window is \(ERTime.dayLabel(next.day)) at \(next.timeText).",
                            actionTitle: nil,
                            action: nil)
        }
        return nil
    }

    static func spell(_ number: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
        return number < words.count ? words[number] : "\(number)"
    }

    // MARK: Errands

    func upsert(_ errand: Errand) {
        mutate { data in
            if let index = data.errands.firstIndex(where: { $0.id == errand.id }) {
                data.errands[index] = errand
            } else {
                data.errands.append(errand)
            }
        }
    }

    func delete(errand: Errand) {
        mutate { data in
            data.errands.removeAll { $0.id == errand.id }
            for index in data.errands.indices where data.errands[index].dependsOn == errand.id {
                data.errands[index].dependsOn = nil
            }
            for index in data.runs.indices {
                data.runs[index].stops.removeAll { $0.errandID == errand.id }
            }
        }
    }

    func setState(_ state: ErrandState, for errand: Errand, doneAt: Date? = nil) {
        mutate { data in
            guard let index = data.errands.firstIndex(where: { $0.id == errand.id }) else { return }
            data.errands[index].state = state
            data.errands[index].doneAt = state == .done ? (doneAt ?? Date()) : nil
            if state == .done, var recurrence = data.errands[index].recurrence {
                recurrence.lastDone = Date()
                recurrence.nextDue = ERTime.adding(days: recurrence.intervalDays, to: Date())
                data.errands[index].recurrence = recurrence
                data.errands[index].state = .open
                data.errands[index].doneAt = nil
            }
        }
    }

    func errandsDepending(on errand: Errand) -> [Errand] {
        data.errands.filter { $0.dependsOn == errand.id }
    }

    // MARK: Places

    func upsert(_ place: Place) {
        mutate { data in
            if let index = data.places.firstIndex(where: { $0.id == place.id }) {
                data.places[index] = place
            } else {
                data.places.append(place)
            }
        }
    }

    func delete(place: Place) {
        mutate { data in
            data.places.removeAll { $0.id == place.id }
            for index in data.errands.indices where data.errands[index].placeID == place.id {
                data.errands[index].placeID = nil
            }
            data.travel = data.travel.filter { !$0.key.contains(place.id.uuidString) }
            for index in data.windows.indices {
                if data.windows[index].from == .place(place.id) { data.windows[index].from = .home }
                if data.windows[index].to == .place(place.id) { data.windows[index].to = .home }
            }
        }
    }

    func errands(at place: Place) -> [Errand] {
        data.errands.filter { $0.placeID == place.id }
    }

    // MARK: Windows

    func upsert(_ window: FreeWindow) {
        mutate { data in
            if let index = data.windows.firstIndex(where: { $0.id == window.id }) {
                data.windows[index] = window
            } else {
                data.windows.append(window)
            }
        }
    }

    func delete(window: FreeWindow) {
        mutate { data in data.windows.removeAll { $0.id == window.id } }
    }

    // MARK: Travel

    func setTravel(from: Endpoint, to: Endpoint, mode: TravelMode, minutes: Int, source: TravelSource) {
        mutate { data in
            data.travel[AppData.travelKey(from, to, mode)] = TravelEntry(minutes: minutes, source: source)
        }
    }

    func clearTravel(from: Endpoint, to: Endpoint, mode: TravelMode) {
        mutate { data in
            data.travel.removeValue(forKey: AppData.travelKey(from, to, mode))
            data.travel.removeValue(forKey: AppData.travelKey(to, from, mode))
        }
    }

    // MARK: Runs

    func startRun(from plan: RoutePlan) -> Run {
        var run = Run()
        run.day = plan.instance.day
        run.windowID = plan.instance.window.id
        run.windowTitle = plan.instance.window.title
        run.start = plan.instance.start
        run.end = plan.instance.end
        run.from = plan.instance.window.from
        run.to = plan.instance.window.to
        run.travelMode = plan.instance.window.travelMode
        run.returnTravel = plan.returnTravel
        run.state = .running
        run.startedAt = Date()
        run.stops = plan.stops.map { stop in
            RunStop(errandID: stop.errand.id,
                    placeID: stop.place.id,
                    title: stop.errand.title,
                    placeName: stop.place.name,
                    plannedTravel: stop.travel,
                    plannedArrival: stop.startInside,
                    plannedInside: stop.inside,
                    plannedLeave: stop.leave,
                    queueAllowance: stop.queue,
                    closeTime: stop.close,
                    lastEntry: stop.lastEntry,
                    documents: stop.errand.requiresDocuments ? stop.errand.documents : [])
        }
        run.didNotFit = plan.didNotFit.map { "\($0.place?.name ?? $0.errand.title): \($0.reason)" }

        mutate { data in
            data.runs.insert(run, at: 0)
            data.activeRunID = run.id
            let ids = Set(run.stops.map(\.errandID))
            for index in data.errands.indices where ids.contains(data.errands[index].id) {
                data.errands[index].lastPlannedRunID = run.id
            }
        }
        return run
    }

    var activeRun: Run? {
        guard let id = data.activeRunID else { return nil }
        return data.run(id)
    }

    func update(run: Run) {
        mutate { data in
            if let index = data.runs.firstIndex(where: { $0.id == run.id }) {
                data.runs[index] = run
            }
        }
    }

    func finish(run: Run, state: RunState = .finished) {
        var updated = run
        updated.state = state
        updated.finishedAt = Date()
        mutate { data in
            if let index = data.runs.firstIndex(where: { $0.id == run.id }) {
                data.runs[index] = updated
            }
            data.activeRunID = nil
        }
    }

    /// Records the measured time inside and lets the place learn from it.
    func logVisit(placeID: UUID, errandID: UUID?, estimated: Int, actual: Int, taskMinutes: Int) {
        mutate { data in
            data.visits.append(VisitLog(placeID: placeID,
                                        errandID: errandID,
                                        estimated: estimated,
                                        actual: actual,
                                        taskMinutes: taskMinutes))
        }
    }

    /// The sentence shown after the app updates its own number.
    func learningNote(for placeID: UUID) -> String? {
        let knowledge = planner.queue(for: placeID)
        guard knowledge.learned, let place = data.place(placeID) else { return nil }
        let list = knowledge.recentActuals
        guard list.count >= 3 else { return nil }
        let spoken = list.map(String.init).joined(separator: ", ")
        let updated = knowledge.averageInside
        guard abs(updated - place.queueEstimate) >= 10 else { return nil }
        return "Last three visits here took \(spoken) minutes. Updated from your \(place.queueEstimate) to \(updated)."
    }

    // MARK: Wasted trips

    func add(wastedTrip: WastedTrip) {
        mutate { data in data.wastedTrips.append(wastedTrip) }
    }

    func wastedTrips(at placeID: UUID) -> [WastedTrip] {
        data.wastedTrips.filter { $0.placeID == placeID }.sorted { $0.date > $1.date }
    }

    /// "Hours here were wrong twice. Check before going."
    func wastedWarning(for placeID: UUID) -> String? {
        let trips = wastedTrips(at: placeID)
        let hoursWrong = trips.filter { $0.reason == .wrongHours || $0.reason == .closedUnexpectedly }.count
        if hoursWrong >= 2 {
            return "Hours here were wrong \(hoursWrong == 2 ? "twice" : "\(hoursWrong) times"). Check before going."
        }
        if trips.count >= 2 {
            return "\(trips.count) wasted trips here. Worth calling first."
        }
        return nil
    }

    // MARK: Photos

    func savePhoto(_ imageData: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try imageData.write(to: photosURL.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func photoURL(_ name: String) -> URL { photosURL.appendingPathComponent(name) }

    func deletePhoto(_ name: String) {
        try? FileManager.default.removeItem(at: photoURL(name))
    }

    // MARK: Data management

    func clearHistory() {
        mutate { data in
            data.runs.removeAll()
            data.visits.removeAll()
            data.wastedTrips.removeAll()
            data.activeRunID = nil
            data.errands.removeAll { $0.state == .done || $0.state == .dropped }
        }
        saveNow()
    }

    func deleteEverything() {
        mutate { data in data = AppData() }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: photosURL.path)) ?? [] {
            try? FileManager.default.removeItem(at: photosURL.appendingPathComponent(name))
        }
        saveNow()
    }

    func importBackup(from url: URL) throws {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let raw = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(AppData.self, from: raw)
        mutate { data in data = imported }
        saveNow()
    }
}
