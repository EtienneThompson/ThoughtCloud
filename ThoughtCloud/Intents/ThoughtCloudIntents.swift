import AppIntents
import ThoughtCloudKit

enum CaptureKind: String, AppEnum {
    case todo, thought, review, event

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kind"
    static let caseDisplayRepresentations: [CaptureKind: DisplayRepresentation] = [
        .todo: "Todo",
        .thought: "Thought",
        .review: "Review card",
        .event: "Event",
    ]

    var itemKind: ItemKind { ItemKind(rawValue: rawValue)! }
}

/// "Add to ThoughtCloud": Siri asks for the text and files it without opening the app.
struct AddToThoughtCloudIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to ThoughtCloud"
    static let description = IntentDescription("Capture a todo, thought, review card, or event.")

    @Parameter(title: "Text", requestValueDialog: "What do you want to capture?")
    var text: String

    @Parameter(title: "Kind")
    var kind: CaptureKind?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) as \(\.$kind)")
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = AppState.shared
        let draft = app.parser.parse(text)
        guard !draft.isEmpty else { return .result(dialog: "There was nothing to add.") }
        let finalKind = kind?.itemKind ?? draft.suggestedKind
        let categoryIDs = app.library.categoryIDs(forHashtags: draft.hashtags)
        let item = app.library.add(
            kind: finalKind,
            title: draft.title,
            body: draft.body,
            categoryIDs: categoryIDs,
            date: finalKind == .thought ? nil : draft.detectedDate
        )
        return .result(dialog: "Added to \(finalKind.plural): \(item.displayTitle)")
    }
}

/// Opens the app straight into the capture sheet (good for the Action button).
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Capture"
    static let description = IntentDescription("Opens ThoughtCloud ready to type.")
    static let openAppWhenRun = true

    @Parameter(title: "Kind")
    var kind: CaptureKind?

    @MainActor func perform() async throws -> some IntentResult {
        AppState.shared.presentCapture(kind: kind?.itemKind)
        return .result()
    }
}

struct StartReviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Review"
    static let description = IntentDescription("Opens the review cards that are due.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        AppState.shared.capture = nil
        AppState.shared.openReview(category: nil)
        return .result()
    }
}

struct ThoughtCloudShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToThoughtCloudIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Capture in \(.applicationName)",
                "Remember something in \(.applicationName)",
            ],
            shortTitle: "Add",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: OpenCaptureIntent(),
            phrases: [
                "Open \(.applicationName) capture",
                "New \(.applicationName) note",
            ],
            shortTitle: "Capture",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: StartReviewIntent(),
            phrases: [
                "Review my \(.applicationName) cards",
                "Start \(.applicationName) review",
            ],
            shortTitle: "Review",
            systemImageName: "rectangle.stack"
        )
    }
}
