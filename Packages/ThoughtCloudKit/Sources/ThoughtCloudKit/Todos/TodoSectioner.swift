import Foundation

public struct TodoSection: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case today, upcoming, someday, done

        public var title: String {
            switch self {
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .someday: "Someday"
            case .done: "Done"
            }
        }
    }

    public var kind: Kind
    public var items: [Item]
    public var id: Kind { kind }
}

/// Groups todos with zero required decisions: no date means Someday.
public struct TodoSectioner: Sendable {
    public var calendar: Calendar
    public var doneWindowDays: Int

    public init(calendar: Calendar = .current, doneWindowDays: Int = 7) {
        self.calendar = calendar
        self.doneWindowDays = doneWindowDays
    }

    public func sections(for items: [Item], now: Date) -> [TodoSection] {
        let todos = items.filter { $0.kind == .todo && !$0.isArchived }
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let doneCutoff = calendar.date(byAdding: .day, value: -doneWindowDays, to: now)!

        var today: [Item] = [], upcoming: [Item] = [], someday: [Item] = [], done: [Item] = []
        for item in todos {
            if let completed = item.completedAt {
                if completed >= doneCutoff { done.append(item) }
            } else if let due = item.dueDate {
                (due < startOfTomorrow) ? today.append(item) : upcoming.append(item)
            } else {
                someday.append(item)
            }
        }

        let byDue: (Item, Item) -> Bool = { ($0.dueDate ?? .distantFuture, $0.createdAt) < ($1.dueDate ?? .distantFuture, $1.createdAt) }
        return [
            TodoSection(kind: .today, items: today.sorted(by: byDue)),
            TodoSection(kind: .upcoming, items: upcoming.sorted(by: byDue)),
            TodoSection(kind: .someday, items: someday.sorted { $0.createdAt > $1.createdAt }),
            TodoSection(kind: .done, items: done.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }),
        ].filter { !$0.items.isEmpty }
    }

    public func isOverdue(_ item: Item, now: Date) -> Bool {
        guard item.kind == .todo, !item.isCompleted, let due = item.dueDate else { return false }
        if item.dueHasTime { return due < now }
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }
}
