import Foundation

/// What gets written to the iPhone Calendar for an event.
public struct CalendarEventDraft: Equatable, Sendable {
    public var title: String
    public var notes: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(title: String, notes: String, start: Date, end: Date, isAllDay: Bool) {
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }

    public init(item: Item, event: EventInfo) {
        self.init(title: item.displayTitle, notes: item.body, start: event.start, end: event.end, isAllDay: event.isAllDay)
    }
}

public enum CalendarSyncError: Error, Sendable {
    /// Calendar access hasn't been granted (yet). Not shown as an error; synced later.
    case notAuthorized
}

/// Seam to the system calendar (EventKit in the app, a spy in tests).
@MainActor
public protocol CalendarSyncing: AnyObject {
    /// Creates or updates the calendar event; returns its identifier.
    func save(_ draft: CalendarEventDraft, existingID: String?) throws -> String
    func remove(id: String) throws
}
