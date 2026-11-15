import Foundation

/// The kinds of thing you can write down.
public enum ItemKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case todo, thought, review, event
    public var id: String { rawValue }
}

/// Spaced-repetition bookkeeping for review items.
public struct ReviewState: Codable, Hashable, Sendable {
    /// Index into the scheduler's interval ladder used by the next "got it".
    public var step: Int
    public var nextReviewAt: Date
    public var lastReviewedAt: Date?
    public var seenCount: Int
    /// Optional "remember until" date. After this day passes the card retires itself.
    public var rememberUntil: Date?

    public init(step: Int = 0, nextReviewAt: Date, lastReviewedAt: Date? = nil, seenCount: Int = 0, rememberUntil: Date? = nil) {
        self.step = step
        self.nextReviewAt = nextReviewAt
        self.lastReviewedAt = lastReviewedAt
        self.seenCount = seenCount
        self.rememberUntil = rememberUntil
    }
}

/// When an event happens, and its link to the iPhone Calendar.
public struct EventInfo: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Whether this event should exist in the iPhone Calendar.
    public var addToCalendar: Bool
    /// EventKit identifier once it has been written to the calendar.
    public var calendarEventID: String?

    public init(start: Date, end: Date, isAllDay: Bool, addToCalendar: Bool = true, calendarEventID: String? = nil) {
        self.start = start
        self.end = max(end, start)
        self.isAllDay = isAllDay
        self.addToCalendar = addToCalendar
        self.calendarEventID = calendarEventID
    }

    /// A timed date lasts an hour; a date without a time (or none) is all day.
    public static func make(from date: DetectedDate?, now: Date, calendar: Calendar) -> EventInfo {
        if let date, date.hasTime {
            return EventInfo(start: date.date, end: date.date.addingTimeInterval(3600), isAllDay: false)
        }
        let day = calendar.startOfDay(for: date?.date ?? now)
        return EventInfo(start: day, end: day, isAllDay: true)
    }
}

/// One step of a todo. Added only while editing a todo, never at capture.
public struct Subtask: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var completedAt: Date?

    public init(id: UUID = UUID(), title: String, createdAt: Date, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }
}

public struct SubtaskProgress: Hashable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// A single captured thing. One type for all kinds so that switching kind or
/// promoting a thought never loses data.
public struct Item: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var title: String
    public var body: String
    /// Ordered: the order categories were picked drives colour blending.
    public var categoryIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    // Todo
    public var dueDate: Date?
    /// Whether `dueDate` carries a meaningful time of day.
    public var dueHasTime: Bool
    public var completedAt: Date?
    /// Ordered steps. Kept if the kind changes, but only used by todos.
    public var subtasks: [Subtask]

    // Review (kept even if kind changes, so history survives round trips)
    public var review: ReviewState?

    // Event
    public var event: EventInfo?

    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: ItemKind,
        title: String,
        body: String = "",
        categoryIDs: [UUID] = [],
        createdAt: Date,
        dueDate: Date? = nil,
        dueHasTime: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.categoryIDs = categoryIDs
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.dueDate = dueDate
        self.dueHasTime = dueHasTime
        self.completedAt = nil
        self.subtasks = []
        self.review = kind == .review ? ReviewState(nextReviewAt: createdAt) : nil
        self.event = nil
        self.archivedAt = nil
    }

    public var isCompleted: Bool { completedAt != nil }
    /// Shows up in the Review deck.
    public var isReviewable: Bool { (kind == .review || kind == .event) && review != nil }
    public var isArchived: Bool { archivedAt != nil }

    public var subtaskProgress: SubtaskProgress {
        SubtaskProgress(done: subtasks.filter(\.isCompleted).count, total: subtasks.count)
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    public mutating func changeKind(to newKind: ItemKind, now: Date) {
        guard newKind != kind else { return }
        if kind == .todo { completedAt = nil }
        kind = newKind
        if newKind == .review && review == nil {
            review = ReviewState(nextReviewAt: now)
        }
        updatedAt = now
    }
}

extension Item {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, body, categoryIDs, createdAt, updatedAt
        case dueDate, dueHasTime, completedAt, subtasks, review, event, archivedAt
    }

    /// Files written before subtasks existed have no `subtasks` key.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ItemKind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        categoryIDs = try c.decode([UUID].self, forKey: .categoryIDs)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        dueHasTime = try c.decode(Bool.self, forKey: .dueHasTime)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        review = try c.decodeIfPresent(ReviewState.self, forKey: .review)
        event = try c.decodeIfPresent(EventInfo.self, forKey: .event)
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}

public enum LinkKind: String, Codable, Sendable {
    /// Created automatically when a thought is turned into a todo / review.
    case promoted
    /// Created by the user.
    case manual
}

/// An undirected connection between two items, shown as an edge in the Cloud.
public struct ItemLink: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var from: UUID
    public var to: UUID
    public var kind: LinkKind
    public var createdAt: Date

    public init(id: UUID = UUID(), from: UUID, to: UUID, kind: LinkKind, createdAt: Date) {
        self.id = id
        self.from = from
        self.to = to
        self.kind = kind
        self.createdAt = createdAt
    }

    public func connects(_ a: UUID, _ b: UUID) -> Bool {
        (from == a && to == b) || (from == b && to == a)
    }

    public func other(than id: UUID) -> UUID? {
        if from == id { return to }
        if to == id { return from }
        return nil
    }
}
