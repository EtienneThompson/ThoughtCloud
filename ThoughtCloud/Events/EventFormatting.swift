import Foundation
import ThoughtCloudKit

nonisolated extension EventInfo {
    /// "Sat, Nov 14 · 7:00 – 8:00 PM", "Fri, Dec 18 – Mon, Dec 21", "Sat, Nov 14".
    var whenText: String {
        let calendar = Calendar.current
        let day = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let sameDay = calendar.isDate(start, inSameDayAs: end)
        if isAllDay {
            return sameDay ? day : day + " – " + end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        let startTime = start.formatted(date: .omitted, time: .shortened)
        if sameDay {
            return end > start ? "\(day) · \(startTime) – \(end.formatted(date: .omitted, time: .shortened))" : "\(day) · \(startTime)"
        }
        return "\(day) \(startTime) – " + end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    /// "7:00 – 8:00 PM" or "All day" (for rows that already show the date).
    var timeText: String {
        if isAllDay {
            return Calendar.current.isDate(start, inSameDayAs: end)
                ? "All day"
                : "All day · until " + end.formatted(.dateTime.weekday(.abbreviated).day())
        }
        let startTime = start.formatted(date: .omitted, time: .shortened)
        return end > start ? "\(startTime) – \(end.formatted(date: .omitted, time: .shortened))" : startTime
    }

    func countdownText(now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
        switch days {
        case ..<0: return now < end ? "Now" : "Past"
        case 0: return now >= start && now < end ? "Now" : "Today"
        case 1: return "Tomorrow"
        case 2..<14: return "in \(days) days"
        case 14..<60: return "in \(days / 7) weeks"
        default: return "in \(days / 30) months"
        }
    }

    /// Compact badge for lists: "Today", "2d", "3w", "5mo".
    func shortCountdown(now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1..<14: return "\(days)d"
        case 14..<60: return "\(days / 7)w"
        default: return "\(days / 30)mo"
        }
    }
}
