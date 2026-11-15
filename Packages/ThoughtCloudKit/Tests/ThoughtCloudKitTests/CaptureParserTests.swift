import Foundation
import Testing
@testable import ThoughtCloudKit

/// Returns a canned date whenever the text contains `trigger`.
struct FakeDateDetector: DateDetecting {
    var trigger: String
    var result: DetectedDate

    func detectDate(in text: String) -> DetectedDate? {
        text.localizedCaseInsensitiveContains(trigger) ? result : nil
    }

    static let none = FakeDateDetector(trigger: "\u{0}never\u{0}", result: DetectedDate(date: .distantPast, hasTime: false, matchedText: ""))
}

@Suite("Capture parser")
struct CaptureParserTests {
    let parser = CaptureParser(dateDetector: FakeDateDetector.none)

    // MARK: Title / body

    @Test func firstLineIsTitleRestIsBody() {
        let draft = parser.parse("Priya\nPartner: Dan\nKids: Ava, Leo")
        #expect(draft.title == "Priya")
        #expect(draft.body == "Partner: Dan\nKids: Ava, Leo")
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        let draft = parser.parse("  \n  Hello there  \n\n")
        #expect(draft.title == "Hello there")
        #expect(draft.body == "")
        #expect(!draft.isEmpty)
        #expect(parser.parse("   \n ").isEmpty)
    }

    // MARK: Hashtags

    @Test func hashtagsAreExtractedAndRemovedFromText() {
        let draft = parser.parse("Prep slides for the sync #work #side-projects")
        #expect(draft.title == "Prep slides for the sync")
        #expect(draft.hashtags == ["work", "side-projects"])
    }

    @Test func hashtagsInTheMiddleLeaveCleanSpacing() {
        let draft = parser.parse("Ask #work about budget")
        #expect(draft.title == "Ask about budget")
    }

    @Test func duplicateHashtagsCollapseCaseInsensitively() {
        #expect(parser.parse("x #Work #work").hashtags == ["Work"])
    }

    @Test func aLoneHashOrNumberIsNotATag() {
        let draft = parser.parse("Room # 4 and #1 fan")
        #expect(draft.hashtags == [])
        #expect(draft.title == "Room # 4 and #1 fan")
    }

    @Test func hashtagInProgressIsReportedForAutocomplete() {
        #expect(parser.parse("Call mom #fam").hashtagInProgress == "fam")
        #expect(parser.parse("Call mom #fam ").hashtagInProgress == nil)
        #expect(parser.parse("Call mom #").hashtagInProgress == "")
    }

    // MARK: Kind guessing

    @Test(arguments: [
        "Call the dentist about the crown",
        "book flights for Dec",
        "Send Q4 deck to Priya",
        "Remember to water the plants",
        "Don't forget to renew passport",
        "Review the on-call doc",
    ])
    func imperativeTextIsATodo(_ text: String) {
        #expect(parser.parse(text).suggestedKind == .todo)
    }

    @Test(arguments: [
        "What if standup was async on Fridays?",
        "Band name: Quiet Static",
        "Plant watering tracker that uses the weather",
    ])
    func everythingElseDefaultsToAThought(_ text: String) {
        #expect(parser.parse(text).suggestedKind == .thought)
    }

    @Test func rememberThatIsAReview() {
        #expect(parser.parse("Remember that Sam hates surprises").suggestedKind == .review)
    }

    @Test func aDatedStatementWithoutATimeIsAReview() {
        let parser = CaptureParser(dateDetector: FakeDateDetector(trigger: "Thursday", result: DetectedDate(date: day(12), hasTime: false, matchedText: "Thursday")))
        let draft = parser.parse("Mom's flight lands Thursday")
        #expect(draft.suggestedKind == .review)
        #expect(draft.detectedDate?.date == day(12))
    }

    @Test func aDatedImperativeIsStillATodo() {
        let parser = CaptureParser(dateDetector: FakeDateDetector(trigger: "tomorrow", result: DetectedDate(date: day(11), hasTime: true, matchedText: "tomorrow at 10")))
        #expect(parser.parse("Call the dentist tomorrow at 10").suggestedKind == .todo)
    }

    @Test func aBodyOfLabelledLinesIsAReview() {
        #expect(parser.parse("Priya\nPartner: Dan\nKids: Ava, Leo").suggestedKind == .review)
    }

    @Test(arguments: [
        ("todo: Something vague", ItemKind.todo, "Something vague"),
        ("t: x", .todo, "x"),
        ("idea: Call it Quiet Static", .thought, "Call it Quiet Static"),
        ("thought: hmm", .thought, "hmm"),
        ("review: On-call rules", .review, "On-call rules"),
        ("remember: Gate code 4412", .review, "Gate code 4412"),
    ])
    func explicitPrefixesWinAndAreStripped(_ text: String, _ kind: ItemKind, _ title: String) {
        let draft = parser.parse(text)
        #expect(draft.suggestedKind == kind)
        #expect(draft.title == title)
    }

    @Test func dateDetectionOnlyLooksAtTheTitle() {
        let parser = CaptureParser(dateDetector: FakeDateDetector(trigger: "Dec 18", result: DetectedDate(date: day(18, month: 12), hasTime: false, matchedText: "Dec 18")))
        #expect(parser.parse("Lisbon trip\n- Dec 18: flight").detectedDate == nil)
    }
}

@Suite("Category name matching")
struct CategoryMatcherTests {
    @Test func normalisesCaseSpacesAndDashes() {
        #expect(CategoryMatcher.key("Side Projects") == CategoryMatcher.key("side-projects"))
        #expect(CategoryMatcher.key("Work") == CategoryMatcher.key("#work"))
    }

    @Test func displayNameFromHashtagIsTitleCased() {
        #expect(CategoryMatcher.displayName(fromHashtag: "side-projects") == "Side Projects")
        #expect(CategoryMatcher.displayName(fromHashtag: "work") == "Work")
    }
}

@Suite("System date detector")
struct SystemDateDetectorTests {
    let detector = SystemDateDetector()

    @Test func findsRelativeDatesWithTime() throws {
        let found = try #require(detector.detectDate(in: "Call the dentist tomorrow at 10"))
        #expect(found.hasTime)
        #expect(found.matchedText == "tomorrow at 10")
    }

    @Test func dateOnlyPhrasesHaveNoTime() throws {
        let found = try #require(detector.detectDate(in: "Wedding RSVP deadline Jan 10"))
        #expect(!found.hasTime)
    }

    @Test func noDateReturnsNil() {
        #expect(detector.detectDate(in: "Band name: Quiet Static") == nil)
    }
}
