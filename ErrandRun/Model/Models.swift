//
//  Models.swift
//  ErrandRun
//
//  Everything the app stores. Local only, no accounts.
//

import Foundation
import SwiftUI

// MARK: - Small value types

struct GeoPoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
}

enum Endpoint: Codable, Hashable {
    case home
    case work
    case place(UUID)
    case custom(String)

    /// Cache key for travel times.
    var key: String {
        switch self {
        case .home: return "home"
        case .work: return "work"
        case .place(let id): return id.uuidString
        case .custom(let name): return "custom:\(name.lowercased())"
        }
    }

    /// One flat string on the wire. An enum with associated values would encode as
    /// a nested object, and an empty JSON object does not survive every server's
    /// decoder intact — a string always does.
    var wireValue: String {
        switch self {
        case .home: return "home"
        case .work: return "work"
        case .place(let id): return "place:\(id.uuidString)"
        case .custom(let name): return "custom:\(name)"
        }
    }

    init(wireValue: String) {
        if wireValue == "home" {
            self = .home
        } else if wireValue == "work" {
            self = .work
        } else if wireValue.hasPrefix("place:"),
                  let id = UUID(uuidString: String(wireValue.dropFirst("place:".count))) {
            self = .place(id)
        } else if wireValue.hasPrefix("custom:") {
            self = .custom(String(wireValue.dropFirst("custom:".count)))
        } else {
            self = .home
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }

    init(from decoder: Decoder) throws {
        // New format: a plain string.
        if let container = try? decoder.singleValueContainer(),
           let text = try? container.decode(String.self) {
            self = Endpoint(wireValue: text)
            return
        }

        // Files written before this change used the synthesised keyed form.
        enum LegacyKey: String, CodingKey { case home, work, place, custom }
        struct LegacyValue: Decodable { let _0: String? }

        let container = try decoder.container(keyedBy: LegacyKey.self)
        if container.contains(.home) {
            self = .home
        } else if container.contains(.work) {
            self = .work
        } else if let wrapped = try? container.decode(LegacyValue.self, forKey: .place),
                  let raw = wrapped._0, let id = UUID(uuidString: raw) {
            self = .place(id)
        } else if let wrapped = try? container.decode(LegacyValue.self, forKey: .custom),
                  let raw = wrapped._0 {
            self = .custom(raw)
        } else {
            self = .home
        }
    }
}

enum Category: String, Codable, CaseIterable, Identifiable, Hashable {
    case health, post, shopping, documents, repair, bank, school, pets, home, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health: return "Health"
        case .post: return "Post"
        case .shopping: return "Shopping"
        case .documents: return "Documents"
        case .repair: return "Repair"
        case .bank: return "Bank"
        case .school: return "School"
        case .pets: return "Pets"
        case .home: return "Home"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .health: return "cross.case.fill"
        case .post: return "envelope.fill"
        case .shopping: return "cart.fill"
        case .documents: return "doc.text.fill"
        case .repair: return "wrench.and.screwdriver.fill"
        case .bank: return "banknote.fill"
        case .school: return "graduationcap.fill"
        case .pets: return "pawprint.fill"
        case .home: return "house.fill"
        case .other: return "diamond.fill"
        }
    }
}

enum TravelMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case walking, cycling, driving, transit, mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .driving: return "Driving"
        case .transit: return "Public Transport"
        case .mixed: return "Mixed"
        }
    }

    /// Used in sentences: "8 minutes drive".
    var noun: String {
        switch self {
        case .walking: return "walk"
        case .cycling: return "ride"
        case .driving: return "drive"
        case .transit: return "on transport"
        case .mixed: return "travel"
        }
    }

    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .driving: return "car.fill"
        case .transit: return "bus.fill"
        case .mixed: return "arrow.triangle.swap"
        }
    }

    /// Rough door-to-door speed in km/h, used only when a real route is unavailable.
    func speed(pace: WalkingPace) -> Double {
        switch self {
        case .walking: return pace.speed
        case .cycling: return 15
        case .driving: return 26
        case .transit: return 17
        case .mixed: return 20
        }
    }
}

enum WalkingPace: String, Codable, CaseIterable, Identifiable, Hashable {
    case slow, normal, brisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .brisk: return "Brisk"
        }
    }

    var speed: Double {
        switch self {
        case .slow: return 4.0
        case .normal: return 4.8
        case .brisk: return 5.6
        }
    }
}

enum ParkingDifficulty: String, Codable, CaseIterable, Identifiable, Hashable {
    case easy, moderate, hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Takes a while"
        case .hard: return "Hard"
        }
    }

    /// Extra minutes on arrival, on top of the buffer between stops.
    var extraMinutes: Int {
        switch self {
        case .easy: return 0
        case .moderate: return 3
        case .hard: return 6
        }
    }
}

enum Priority: String, Codable, CaseIterable, Identifiable, Hashable {
    case low, normal, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    var rank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

// MARK: - Opening hours

struct DayHours: Codable, Hashable {
    var isOpen: Bool = true
    var open: Int = 9 * 60
    var close: Int = 18 * 60
    var hasLunch: Bool = false
    var lunchStart: Int = 13 * 60
    var lunchEnd: Int = 14 * 60
    /// Minutes before closing after which they no longer let anyone in.
    var lastEntryOffset: Int = 0

    var lastEntry: Int { close - lastEntryOffset }

    static let closed = DayHours(isOpen: false)

    var text: String {
        guard isOpen else { return "Closed" }
        var result = "\(ERTime.time(open))–\(ERTime.time(close))"
        if hasLunch {
            result += ", lunch \(ERTime.time(lunchStart))–\(ERTime.time(lunchEnd))"
        }
        if lastEntryOffset > 0 {
            result += ", last entry \(ERTime.time(lastEntry))"
        }
        return result
    }

    var shortText: String {
        isOpen ? "\(ERTime.time(open))–\(ERTime.time(close))" : "Closed"
    }
}

struct WeeklyHours: Codable, Hashable {
    /// Indexed by Calendar weekday (1 = Sunday) minus one.
    var days: [DayHours]

    init(days: [DayHours]? = nil) {
        if let days, days.count == 7 {
            self.days = days
        } else {
            self.days = Array(repeating: DayHours(), count: 7)
        }
    }

    subscript(weekday: Int) -> DayHours {
        get { days[max(1, min(7, weekday)) - 1] }
        set { days[max(1, min(7, weekday)) - 1] = newValue }
    }

    static var standard: WeeklyHours {
        var hours = WeeklyHours()
        for weekday in 1...7 {
            if weekday == 1 || weekday == 7 {
                hours[weekday] = .closed
            } else {
                hours[weekday] = DayHours()
            }
        }
        return hours
    }

    /// A compact description like "Mon–Fri 09:00–18:00 · Sat 10:00–15:00 · Sun closed".
    var summary: String {
        var chunks: [String] = []
        var index = 0
        let order = ERTime.weekOrder
        while index < order.count {
            let day = self[order[index]]
            var last = index
            while last + 1 < order.count, self[order[last + 1]] == day { last += 1 }
            let name = ERTime.weekdayName(order[index], short: true)
            let label: String
            if last > index {
                label = "\(name)–\(ERTime.weekdayName(order[last], short: true))"
            } else {
                label = name
            }
            chunks.append("\(label) \(day.shortText)")
            index = last + 1
        }
        return chunks.joined(separator: " · ")
    }
}

// MARK: - Place

struct Place: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var address = ""
    var category: Category = .other
    var hours = WeeklyHours.standard
    var parking: ParkingDifficulty = .easy
    /// The user's own guess, never the app's promise.
    var queueEstimate = 10
    var notes = ""
    var photos: [String] = []
    var coordinate: GeoPoint?
    var createdAt = Date()
    /// When the user last edited this. Optional so older saved files still load.
    var updatedAt: Date?

    func hours(on date: Date) -> DayHours { hours[ERTime.weekday(date)] }

    func isOpen(on date: Date) -> Bool { hours(on: date).isOpen }

    var endpoint: Endpoint { .place(id) }
}

// MARK: - Errand

enum ErrandState: String, Codable, Hashable {
    case open, done, dropped
}

/// What the errand list actually shows as a section.
enum ErrandSection: String, CaseIterable, Identifiable, Hashable {
    case open = "Open"
    case scheduled = "Scheduled"
    case waiting = "Waiting for a Window"
    case blocked = "Blocked"
    case done = "Done"
    case dropped = "Dropped"

    var id: String { rawValue }

    var tone: ERStatusTone {
        switch self {
        case .open: return .idle
        case .scheduled: return .active
        case .waiting: return .waiting
        case .blocked: return .blocked
        case .done: return .done
        case .dropped: return .dropped
        }
    }
}

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var quantity = ""
    var note = ""
    var bought = false
}

struct Recurrence: Codable, Hashable {
    var intervalDays = 7
    var nextDue = Date()
    var lastDone: Date?
    /// How far it may slide while waiting for a window that fits.
    var flexibleByDays = 3

    var intervalTitle: String {
        switch intervalDays {
        case 1: return "Every day"
        case 7: return "Every week"
        case 14: return "Every two weeks"
        case 30: return "Every month"
        case 90: return "Every three months"
        case 180: return "Every six months"
        case 365: return "Every year"
        default: return "Every \(intervalDays) days"
        }
    }

    static let presets = [7, 14, 30, 90, 180, 365]
}

enum DelegationStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case notAssigned, assigned, shared, doneByThem, declined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notAssigned: return "Not assigned"
        case .assigned: return "Assigned"
        case .shared: return "Instructions shared"
        case .doneByThem: return "Done by them"
        case .declined: return "Declined"
        }
    }
}

struct Delegation: Codable, Hashable {
    var assignedTo = ""
    var instructions = ""
    var status: DelegationStatus = .notAssigned
}

struct Errand: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = ""
    var placeID: UUID?
    var category: Category = .other
    /// How long the thing itself takes. No travel, no queue.
    var duration = 15
    var deadline: Date?
    var priority: Priority = .normal
    var requiresDocuments = false
    var documents: [String] = []
    var canBeDelegated = false
    var dependsOn: UUID?
    var notes = ""
    var state: ErrandState = .open
    var doneAt: Date?
    var shopping: [ShoppingItem] = []
    var recurrence: Recurrence?
    var delegation: Delegation?
    var createdAt = Date()
    /// Set when the errand is planned into a run.
    var lastPlannedRunID: UUID?
    var updatedAt: Date?

    var isShopping: Bool { category == .shopping }
}

// MARK: - Free window

struct FreeWindow: Identifiable, Codable, Hashable {
    var id = UUID()
    var title = ""
    var isRecurring = true
    /// Calendar weekdays, 1 = Sunday.
    var weekdays: [Int] = [2, 3, 4, 5, 6]
    var date: Date?
    var start = 13 * 60
    var end = 14 * 60 + 30
    var from: Endpoint = .work
    var to: Endpoint = .home
    var travelMode: TravelMode = .driving
    var isEnabled = true
    var updatedAt: Date?

    var lengthMinutes: Int { max(0, end - start) }

    var daysText: String {
        if !isRecurring {
            return date.map { ERTime.dayLabel($0) } ?? "One-off"
        }
        if weekdays.isEmpty { return "No days" }
        if Set(weekdays) == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if Set(weekdays) == Set([1, 7]) { return "Weekend" }
        if weekdays.count == 7 { return "Every day" }
        return ERTime.weekOrder
            .filter { weekdays.contains($0) }
            .map { ERTime.weekdayName($0, short: true) }
            .joined(separator: ", ")
    }

    var timeText: String { "\(ERTime.time(start))–\(ERTime.time(end))" }

    func occurs(on day: Date) -> Bool {
        guard isEnabled else { return false }
        if isRecurring { return weekdays.contains(ERTime.weekday(day)) }
        guard let date else { return false }
        return ERTime.isSameDay(date, day)
    }
}

/// A concrete occurrence of a window on a date.
struct WindowInstance: Identifiable, Hashable {
    var window: FreeWindow
    var day: Date
    /// Set when the window is already running: planning starts from the clock, not from
    /// the time the window opened. A route through minutes that have already passed is fiction.
    var startFrom: Int?

    var id: String { "\(window.id.uuidString)-\(Int(ERTime.startOfDay(day).timeIntervalSince1970))" }
    var start: Int { max(window.start, startFrom ?? window.start) }
    var end: Int { window.end }
    var minutes: Int { max(0, end - start) }
    var isRunning: Bool { (startFrom ?? window.start) > window.start }

    var startsAt: Date { ERTime.date(fromMinutes: start, on: day) }
    var endsAt: Date { ERTime.date(fromMinutes: window.end, on: day) }

    var timeText: String { "\(ERTime.time(start))–\(ERTime.time(end))" }

    var label: String {
        let name = window.title.isEmpty ? ERTime.dayLabel(day) : window.title
        return "\(name), \(timeText)"
    }
}

// MARK: - Run

enum RunState: String, Codable, Hashable {
    case planned, running, finished, abandoned
}

enum StopState: String, Codable, Hashable {
    case pending, arrived, done, skipped
}

struct RunStop: Identifiable, Codable, Hashable {
    var id = UUID()
    var errandID: UUID
    var placeID: UUID?
    var title = ""
    var placeName = ""
    var plannedTravel = 0
    var plannedArrival = 0
    var plannedInside = 0
    var plannedLeave = 0
    var queueAllowance = 0
    var closeTime: Int?
    var lastEntry: Int?
    var documents: [String] = []
    var state: StopState = .pending
    var arrivedAt: Date?
    var actualInside: Int?
    var skipReason: String?
}

struct Run: Identifiable, Codable, Hashable {
    var id = UUID()
    var day = Date()
    var windowID: UUID?
    var windowTitle = ""
    var start = 0
    var end = 0
    var from: Endpoint = .home
    var to: Endpoint = .home
    var travelMode: TravelMode = .driving
    var stops: [RunStop] = []
    var didNotFit: [String] = []
    var state: RunState = .planned
    var startedAt: Date?
    var finishedAt: Date?
    var lateMinutes = 0
    var returnTravel = 0
    var updatedAt: Date?

    var doneCount: Int { stops.filter { $0.state == .done }.count }
    var skippedCount: Int { stops.filter { $0.state == .skipped }.count }
    var plannedMinutes: Int { max(0, end - start) }

    var currentIndex: Int? {
        stops.firstIndex { $0.state == .pending || $0.state == .arrived }
    }
}

// MARK: - Measurements the app learns from

struct VisitLog: Identifiable, Codable, Hashable {
    var id = UUID()
    var placeID: UUID
    var errandID: UUID?
    var date = Date()
    /// What the app planned for the time inside: the errand plus the queue allowance.
    var estimated = 0
    /// What it actually took, measured by the user.
    var actual = 0
    /// The errand's own duration, so the queue part can be separated out.
    var taskMinutes = 0
    var updatedAt: Date?

    var overhead: Int { max(0, actual - taskMinutes) }
    var drift: Int { actual - estimated }
}

enum WastedReason: String, Codable, CaseIterable, Identifiable, Hashable {
    case closedUnexpectedly, wrongHours, missingDocument, systemDown, wrongPerson, queueTooLong, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closedUnexpectedly: return "Closed Unexpectedly"
        case .wrongHours: return "Wrong Hours Recorded"
        case .missingDocument: return "Missing Document"
        case .systemDown: return "System Down"
        case .wrongPerson: return "Wrong Person"
        case .queueTooLong: return "Queue Too Long"
        case .other: return "Other"
        }
    }
}

struct WastedTrip: Identifiable, Codable, Hashable {
    var id = UUID()
    var placeID: UUID
    var errandID: UUID?
    var date = Date()
    var reason: WastedReason = .closedUnexpectedly
    var missing = ""
    var notes = ""
    var updatedAt: Date?
}

// MARK: - Travel cache

enum TravelSource: String, Codable, Hashable {
    case map, manual, distance

    var title: String {
        switch self {
        case .map: return "From the map"
        case .manual: return "Entered by hand"
        case .distance: return "Estimated from distance"
        }
    }
}

struct TravelEntry: Codable, Hashable {
    var minutes: Int
    var source: TravelSource
    var updatedAt = Date()
}

// MARK: - Settings

struct NotificationPrefs: Codable, Hashable {
    var windowStartsSoon = true
    var leaveBy = true
    var placeClosingToday = true
    var deadlineFewWindows = true
    var errandWaitingTooLong = true
    var logHowLongItTook = true
}

struct Settings: Codable, Hashable {
    var displayName = ""
    var homeAddress = ""
    var homeCoordinate: GeoPoint?
    var workAddress = ""
    var workCoordinate: GeoPoint?
    var travelMode: TravelMode = .driving
    var walkingPace: WalkingPace = .normal
    /// Parking, finding the entrance, the lift. The thing that makes a route real.
    var buffer = 5
    var onboardingSeen = false
    var setupComplete = false
    var notificationsEnabled = false
    var notifications = NotificationPrefs()
    /// Replace the user's guess with their own measured average once there is data.
    var learnFromVisits = true
}

// MARK: - Root document

struct AppData: Codable {
    var settings = Settings()
    var places: [Place] = []
    var errands: [Errand] = []
    var windows: [FreeWindow] = []
    var runs: [Run] = []
    var visits: [VisitLog] = []
    var wastedTrips: [WastedTrip] = []
    var travel: [String: TravelEntry] = [:]
    var activeRunID: UUID?

    // MARK: Sync bookkeeping
    var tombstones: [Tombstone] = []
    var dirty = DirtyIndex()
    var sync = SyncState()

    init() {}

    /// Decoded field by field so a file written by an older build — one that knew
    /// nothing about syncing — still opens instead of throwing the user's data away.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        places = try container.decodeIfPresent([Place].self, forKey: .places) ?? []
        errands = try container.decodeIfPresent([Errand].self, forKey: .errands) ?? []
        windows = try container.decodeIfPresent([FreeWindow].self, forKey: .windows) ?? []
        runs = try container.decodeIfPresent([Run].self, forKey: .runs) ?? []
        visits = try container.decodeIfPresent([VisitLog].self, forKey: .visits) ?? []
        wastedTrips = try container.decodeIfPresent([WastedTrip].self, forKey: .wastedTrips) ?? []
        travel = try container.decodeIfPresent([String: TravelEntry].self, forKey: .travel) ?? [:]
        activeRunID = try container.decodeIfPresent(UUID.self, forKey: .activeRunID)
        tombstones = try container.decodeIfPresent([Tombstone].self, forKey: .tombstones) ?? []
        dirty = try container.decodeIfPresent(DirtyIndex.self, forKey: .dirty) ?? DirtyIndex()
        sync = try container.decodeIfPresent(SyncState.self, forKey: .sync) ?? SyncState()
    }
}
