import EventKit
import Observation
import ThoughtCloudKit

/// Writes ThoughtCloud events to the iPhone Calendar (default calendar).
/// Without access it throws `.notAuthorized`; the library retries once access is granted.
@MainActor
@Observable
final class EventKitCalendar: CalendarSyncing {
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var isRequesting = false
    /// Called after the user grants access, so pending events can be written.
    @ObservationIgnored var onAccessGranted: (() -> Void)?

    private(set) var status = EKEventStore.authorizationStatus(for: .event)
    var hasAccess: Bool { status == .fullAccess }

    /// Re-reads the status (it can change in iOS Settings while the app is in the background).
    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccessIfNeeded() {
        guard status == .notDetermined, !isRequesting else { return }
        isRequesting = true
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            isRequesting = false
            refreshStatus()
            if granted { onAccessGranted?() }
        }
    }

    func save(_ draft: CalendarEventDraft, existingID: String?) throws -> String {
        guard hasAccess else {
            requestAccessIfNeeded()
            throw CalendarSyncError.notAuthorized
        }
        // Recreated if it was deleted in the Calendar app.
        let event = existingID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        if event.calendar == nil {
            guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarError.noDefaultCalendar }
            event.calendar = calendar
        }
        event.title = draft.title
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.end
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? existingID ?? ""
    }

    func remove(id: String) throws {
        guard hasAccess else { throw CalendarSyncError.notAuthorized }
        guard let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    enum CalendarError: LocalizedError {
        case noDefaultCalendar
        var errorDescription: String? { "No default calendar" }
    }
}
