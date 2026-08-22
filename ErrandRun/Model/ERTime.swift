//
//  ERTime.swift
//  ErrandRun
//
//  Everything in the app is minutes from midnight. This turns them into words.
//

import Foundation

enum ERTime {
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    /// "14:05"
    static func time(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    /// "1 h 25 min" / "45 min"
    static func duration(_ minutes: Int) -> String {
        if minutes < 0 { return "0 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "90 minutes"
    static func minutesWord(_ minutes: Int) -> String {
        "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    static func minutes(from date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, on day: Date = Date()) -> Date {
        calendar.date(bySettingHour: min(23, max(0, minutes / 60)),
                      minute: minutes % 60,
                      second: 0,
                      of: calendar.startOfDay(for: day)) ?? day
    }

    static func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
    }

    /// 1 = Sunday ... 7 = Saturday, matching Calendar.
    static func weekday(_ date: Date) -> Int { calendar.component(.weekday, from: date) }

    static func weekdayName(_ weekday: Int, short: Bool = false) -> String {
        let symbols = short ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols
        let index = max(1, min(7, weekday)) - 1
        return symbols[index]
    }

    /// Monday-first order of Calendar weekday numbers.
    static let weekOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    /// "Today", "Tomorrow", "Saturday", "12 March"
    static func dayLabel(_ date: Date) -> String {
        let days = daysBetween(Date(), date)
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days > 1 && days < 7 { return weekdayName(weekday(date)) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }

    /// "today", "tomorrow", "on Saturday", "on 12 March" — made to sit inside a sentence.
    static func dayPhrase(_ date: Date) -> String {
        let days = daysBetween(Date(), date)
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        return "on \(dayLabel(date))"
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }
}
