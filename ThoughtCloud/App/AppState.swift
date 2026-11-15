import Foundation
import Observation
import ThoughtCloudKit

enum AppTab: Hashable {
    case cloud, todos, events, thoughts, review, settings
}

/// What the capture sheet should start with.
struct CaptureRequest: Identifiable {
    let id = UUID()
    var kind: ItemKind?
    var categoryIDs: [UUID] = []
}

/// App-wide navigation state plus the one `Library`. Shared with App Intents
/// so Siri/Shortcuts write to the same in-memory library the UI shows.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let library: Library
    /// Nil in demo mode so sample events never touch the real calendar.
    let calendarSync: EventKitCalendar?
    let parser = CaptureParser(dateDetector: SystemDateDetector())

    var tab: AppTab = .cloud
    var capture: CaptureRequest?
    var detailItemID: UUID?
    /// Category the Review tab should focus on next time it appears.
    var reviewFocus: UUID?

    init(library: Library? = nil) {
        if let library {
            self.library = library
            self.calendarSync = nil
        } else {
            (self.library, self.calendarSync) = Self.makeLibrary()
        }
        calendarSync?.onAccessGranted = { [weak self] in self?.library.syncPendingCalendarEvents() }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tcTab"), i + 1 < args.count {
            tab = ["todos": .todos, "events": .events, "thoughts": .thoughts, "review": .review, "settings": .settings][args[i + 1]] ?? .cloud
        }
        if args.contains("-tcCapture") { capture = CaptureRequest(kind: captureKindForCurrentTab) }
        #endif
    }

    func presentCapture(kind: ItemKind? = nil, categoryIDs: [UUID] = []) {
        detailItemID = nil
        capture = CaptureRequest(kind: kind, categoryIDs: categoryIDs)
    }

    /// The + button starts on the current tab's kind; Cloud and Settings auto-guess.
    var captureKindForCurrentTab: ItemKind? {
        switch tab {
        case .cloud, .settings: nil
        case .todos: .todo
        case .events: .event
        case .thoughts: .thought
        case .review: .review
        }
    }

    func openReview(category: UUID?) {
        reviewFocus = category
        tab = .review
    }

    private static func makeLibrary() -> (Library, EventKitCalendar?) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-tcSampleData") {
            let library = Library(persistence: InMemoryPersistence())
            SampleData.populate(library)
            return (library, nil)
        }
        #endif
        let calendarSync = EventKitCalendar()
        let library = Library(persistence: JSONFilePersistence(directory: JSONFilePersistence.defaultDirectory()), calendarSync: calendarSync)
        let seededKey = "didSeedDefaultCategories"
        if !UserDefaults.standard.bool(forKey: seededKey) {
            library.seedDefaultCategoriesIfNeeded()
            UserDefaults.standard.set(true, forKey: seededKey)
        }
        return (library, calendarSync)
    }
}
