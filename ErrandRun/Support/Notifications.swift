//
//  Notifications.swift
//  ErrandRun
//
//  Local reminders only. Nothing leaves the phone.
//

import Foundation
import UserNotifications

final class Notifications {
    static let shared = Notifications()

    private var work: DispatchWorkItem?
    private let centre = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await centre.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await centre.notificationSettings().authorizationStatus
    }

    func reschedule(store: AppStore) {
        work?.cancel()
        let item = DispatchWorkItem { [weak store] in
            guard let store else { return }
            let requests = Notifications.build(store: store)
            let centre = UNUserNotificationCenter.current()
            centre.removeAllPendingNotificationRequests()
            guard store.data.settings.notificationsEnabled else { return }
            for request in requests.prefix(30) {
                centre.add(request, withCompletionHandler: nil)
            }
        }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    // MARK: Building

    static func build(store: AppStore) -> [UNNotificationRequest] {
        let settings = store.data.settings
        guard settings.notificationsEnabled else { return [] }
        let prefs = settings.notifications
        let planner = store.planner
        var requests: [UNNotificationRequest] = []
        let now = Date()

        // Window starts soon, and the leave-by time computed from travel and buffer.
        for instance in planner.instances(from: now, days: 7).prefix(8) {
            let plan = planner.plan(for: instance)
            guard !plan.stops.isEmpty else { continue }

            if prefs.windowStartsSoon {
                let fireAt = instance.startsAt.addingTimeInterval(-15 * 60)
                if fireAt > now {
                    requests.append(request(
                        id: "window-\(instance.id)",
                        title: "Window Starts Soon",
                        body: "\(instance.timeText). \(plan.stops.count) errand\(plan.stops.count == 1 ? "" : "s") fit, first stop \(plan.stops[0].place.name).",
                        date: fireAt
                    ))
                }
            }

            if prefs.leaveBy {
                let slack = max(0, plan.windowMinutes - plan.usedMinutes)
                let leaveBy = instance.start + slack
                let fireAt = ERTime.date(fromMinutes: max(0, leaveBy - 10), on: instance.day)
                if fireAt > now {
                    requests.append(request(
                        id: "leave-\(instance.id)",
                        title: "Leave By \(ERTime.time(leaveBy))",
                        body: "\(plan.stops[0].travel) minutes \(instance.window.travelMode.noun) to \(plan.stops[0].place.name), plus \(store.data.settings.buffer) minutes of buffer.",
                        date: fireAt
                    ))
                }
            }

            if prefs.placeClosingToday, let earliest = plan.earliestClosing {
                let fireAt = ERTime.date(fromMinutes: max(0, earliest.close - 90), on: instance.day)
                if fireAt > now {
                    requests.append(request(
                        id: "closing-\(instance.id)",
                        title: "\(earliest.place.name) Closes at \(ERTime.time(earliest.close))",
                        body: "It is on today's route. Ninety minutes left.",
                        date: fireAt
                    ))
                }
            }
        }

        // Deadlines measured in windows, not days.
        if prefs.deadlineFewWindows {
            for errand in store.data.errands where errand.state == .open {
                guard let deadline = errand.deadline, deadline > now else { continue }
                let windows = planner.windowsBefore(deadline: deadline, for: errand)
                guard windows.count <= 3 else { continue }
                let fireAt = ERTime.date(fromMinutes: 9 * 60, on: ERTime.adding(days: 1, to: now))
                if fireAt > now {
                    let due: String = ERTime.shortDate(deadline)
                    let count: Int = windows.count
                    let title: String
                    let body: String
                    if count == 0 {
                        title = "No Windows Left for \(errand.title)"
                        body = "\(errand.title) is due \(due) and no window fits it. Delegate it or make time."
                    } else {
                        let plural: String = count == 1 ? "window" : "windows"
                        title = "\(AppStore.spell(count)) Windows Left"
                        body = "\(errand.title) is due \(due). \(AppStore.spell(count)) \(plural) left where the place is open."
                    }
                    requests.append(request(id: "deadline-\(errand.id.uuidString)", title: title, body: body, date: fireAt))
                }
            }
        }

        // Errands that keep waiting.
        if prefs.errandWaitingTooLong {
            let stale = store.data.errands.filter { errand in
                errand.state == .open
                    && store.derived.sections[errand.id] == .waiting
                    && ERTime.daysBetween(errand.createdAt, now) >= 14
            }
            if let first = stale.first {
                let fireAt = ERTime.date(fromMinutes: 10 * 60, on: ERTime.adding(days: 1, to: now))
                if fireAt > now {
                    requests.append(request(
                        id: "waiting-sweep",
                        title: "Errands Keep Waiting",
                        body: stale.count == 1
                            ? "\(first.title) has been waiting two weeks for a window. Maybe it needs its own time, or someone else."
                            : "\(stale.count) errands have been waiting two weeks for a window.",
                        date: fireAt
                    ))
                }
            }
        }

        // Log how long it took.
        if prefs.logHowLongItTook, let run = store.activeRun, run.state == .running {
            let fireAt = ERTime.date(fromMinutes: run.end + 20, on: run.day)
            if fireAt > now {
                requests.append(request(
                    id: "log-\(run.id.uuidString)",
                    title: "Log How Long It Took",
                    body: "Your own numbers are the whole point. It takes ten seconds.",
                    date: fireAt
                ))
            }
        }

        return requests
    }

    private static func request(id: String, title: String, body: String, date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = ERTime.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
