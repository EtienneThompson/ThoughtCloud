import Foundation

public enum EventSection: Hashable, Sendable {
    case thisWeek
    case laterThisMonth
    case month(year: Int, month: Int)
}

public struct EventGroup: Hashable, Sendable {
    public var section: EventSection
    public var items: [Item]
}

/// Groups upcoming events for the Events tab.
public struct EventSectioner: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func sections(for items: [Item], now: Date) -> [EventGroup] {
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let sorted = items.filter { $0.event != nil }.sorted { $0.event!.start < $1.event!.start }
        var groups: [EventGroup] = []
        for item in sorted {
            let start = item.event!.start
            let section: EventSection
            if start < weekEnd {
                section = .thisWeek
            } else if calendar.isDate(start, equalTo: today, toGranularity: .month) {
                section = .laterThisMonth
            } else {
                let parts = calendar.dateComponents([.year, .month], from: start)
                section = .month(year: parts.year ?? 0, month: parts.month ?? 0)
            }
            if groups.last?.section == section {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(EventGroup(section: section, items: [item]))
            }
        }
        return groups
    }

    /// Calendar days from today until the event starts (0 = today or already started).
    public func daysUntil(_ item: Item, now: Date) -> Int {
        guard let start = item.event?.start else { return 0 }
        let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
        return max(0, d)
    }
}
