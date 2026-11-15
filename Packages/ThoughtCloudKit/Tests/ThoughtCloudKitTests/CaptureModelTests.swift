import Foundation
import Testing
@testable import ThoughtCloudKit

@MainActor
@Suite("Capture model")
struct CaptureModelTests {
    let clock = FakeClock(day(10, hour: 9))
    let library: Library
    let model: CaptureModel
    let work: ItemCategory
    let home: ItemCategory

    init() {
        library = Library(persistence: InMemoryPersistence(), dates: clock, calendar: .testUTC)
        work = library.createCategory(name: "Work", emoji: "💼")
        home = library.createCategory(name: "Home", emoji: "🏠")
        model = CaptureModel(library: library, parser: CaptureParser(dateDetector: FakeDateDetector(
            trigger: "tomorrow", result: DetectedDate(date: day(11, hour: 10), hasTime: true, matchedText: "tomorrow at 10"))))
    }

    @Test func typingUpdatesTheSuggestedKind() {
        model.text = "Call the dentist"
        #expect(model.kind == .todo)
        model.text = "What if?"
        #expect(model.kind == .thought)
    }

    @Test func aManuallyChosenKindSticksWhileTyping() {
        model.chooseKind(.review)
        model.text = "Call the dentist"
        #expect(model.kind == .review)
        #expect(model.kindWasChosen)
    }

    @Test func hashtagsSelectMatchingCategories() {
        model.text = "Prep slides #work"
        #expect(model.selectedCategoryIDs == [work.id])
        #expect(model.newCategoryNames == [])
    }

    @Test func unknownHashtagsAreShownAsNewCategories() {
        model.text = "Band name #side-projects"
        #expect(model.newCategoryNames == ["Side Projects"])
    }

    @Test func tappingChipsTogglesCategoriesInPickOrder() {
        model.toggleCategory(home.id)
        model.toggleCategory(work.id)
        #expect(model.selectedCategoryIDs == [home.id, work.id])
        model.toggleCategory(home.id)
        #expect(model.selectedCategoryIDs == [work.id])
    }

    @Test func savingCreatesTheItemAndResetsForTheNextOne() throws {
        model.text = "Call the dentist tomorrow at 10 #work"
        let item = try #require(model.save())
        #expect(item.kind == .todo)
        #expect(item.title == "Call the dentist tomorrow at 10")
        #expect(item.categoryIDs == [work.id])
        #expect(item.dueDate == day(11, hour: 10))
        #expect(model.text == "")
        #expect(!model.kindWasChosen)
        #expect(model.selectedCategoryIDs == [])
    }

    @Test func savingCreatesCategoriesForNewHashtags() throws {
        model.text = "Quiet Static #side-projects"
        let item = try #require(model.save())
        let created = try #require(library.categories.first { $0.name == "Side Projects" })
        #expect(item.categoryIDs == [created.id])
    }

    @Test func dismissingTheDateSavesWithoutIt() throws {
        model.text = "Call the dentist tomorrow at 10"
        #expect(model.detectedDate != nil)
        model.dismissDate()
        #expect(model.detectedDate == nil)
        #expect(try #require(model.save()).dueDate == nil)
    }

    @Test func eventTimesCanBeSetBeforeSaving() throws {
        model.chooseKind(.event)
        model.text = "Dinner with Sam"
        #expect(model.eventPreview?.isAllDay == true)
        model.setEventTimes(start: day(20, hour: 19), end: day(20, hour: 21), isAllDay: false)
        #expect(model.eventPreview?.start == day(20, hour: 19))
        let item = try #require(model.save())
        #expect(item.event?.start == day(20, hour: 19))
        #expect(item.event?.end == day(20, hour: 21))
        #expect(item.event?.isAllDay == false)
    }

    @Test func manualEventTimesWinOverTheDetectedDate() throws {
        model.chooseKind(.event)
        model.setEventTimes(start: day(20, hour: 19), end: day(20, hour: 20), isAllDay: false)
        model.text = "Dinner tomorrow at 10"
        #expect(model.eventPreview?.start == day(20, hour: 19))
        #expect(try #require(model.save()).event?.start == day(20, hour: 19))
    }

    @Test func allDayManualEventsSnapToTheStartOfTheDay() {
        model.chooseKind(.event)
        model.setEventTimes(start: day(20, hour: 19), end: day(21, hour: 8), isAllDay: true)
        #expect(model.eventPreview?.start == day(20, hour: 0))
        #expect(model.eventPreview?.end == day(21, hour: 0))
    }

    @Test func manualEventEndNeverPrecedesStart() {
        model.chooseKind(.event)
        model.setEventTimes(start: day(20, hour: 19), end: day(20, hour: 18), isAllDay: false)
        #expect(model.eventPreview?.end == day(20, hour: 19))
    }

    @Test func dismissingTheDateClearsManualEventTimes() {
        model.chooseKind(.event)
        model.setEventTimes(start: day(20, hour: 19), end: day(20, hour: 20), isAllDay: false)
        model.dismissDate()
        #expect(model.eventPreview?.start == day(10, hour: 0))
        #expect(model.eventPreview?.isAllDay == true)
    }

    @Test func manualEventTimesAreClearedForTheNextCapture() throws {
        model.chooseKind(.event)
        model.text = "Dinner"
        model.setEventTimes(start: day(20, hour: 19), end: day(20, hour: 20), isAllDay: false)
        _ = try #require(model.save())
        model.chooseKind(.event)
        #expect(model.eventPreview?.start == day(10, hour: 0))
    }

    @Test func emptyTextDoesNotSave() {
        model.text = "   "
        #expect(model.save() == nil)
        #expect(library.items.isEmpty)
    }

    @Test func presetCategoriesSurviveReset() throws {
        let model = CaptureModel(library: library, parser: CaptureParser(dateDetector: FakeDateDetector.none), presetCategoryIDs: [home.id])
        model.text = "Fix door"
        _ = try #require(model.save())
        #expect(model.selectedCategoryIDs == [home.id])
    }

    @Test func presetKindSurvivesResetSoNextKeepsTheTabsKind() throws {
        let model = CaptureModel(library: library, parser: CaptureParser(dateDetector: FakeDateDetector.none), presetKind: .todo)
        model.text = "Some idea"
        _ = try #require(model.save())
        #expect(model.kind == .todo)
        model.chooseKind(.review)
        model.reset()
        #expect(model.kind == .todo)
    }

    @Test func recentlyUsedCategoriesComeFirst() {
        clock.current = day(10, hour: 10)
        library.add(kind: .thought, title: "x", categoryIDs: [home.id])
        #expect(model.orderedCategories.map(\.id) == [home.id, work.id])
    }

    @Test func autocompleteFiltersByTheTagBeingTyped() {
        model.text = "Call mom #ho"
        #expect(model.autocomplete.map(\.id) == [home.id])
        model.complete(with: home)
        #expect(model.text == "Call mom #home ")
        #expect(model.autocomplete.isEmpty)
    }

    @Test func autocompleteUsesDashesForMultiWordNames() {
        let side = library.createCategory(name: "Side Projects")
        model.text = "x #si"
        model.complete(with: side)
        #expect(model.text == "x #side-projects ")
        #expect(model.selectedCategoryIDs == [side.id])
    }
}

@MainActor
@Suite("Review session")
struct ReviewSessionTests {
    let clock = FakeClock(day(10, hour: 9))
    let library: Library

    init() {
        library = Library(persistence: InMemoryPersistence(), dates: clock, calendar: .testUTC)
    }

    @Test func walksThroughDueCardsAndGradesThem() {
        let a = library.add(kind: .review, title: "a")
        let b = library.add(kind: .review, title: "b")
        let session = ReviewSession(library: library)
        #expect(session.current?.id == a.id)
        #expect(session.remaining == 2)
        session.swipe(.gotIt)
        #expect(session.current?.id == b.id)
        session.swipe(.again)
        #expect(session.isFinished)
        #expect(library.item(a.id)?.review?.nextReviewAt == day(11, hour: 0))
        #expect(library.item(b.id)?.review?.step == 0)
    }

    @Test func queueIsStableEvenThoughAgainKeepsNothingDueToday() {
        library.add(kind: .review, title: "a")
        let session = ReviewSession(library: library)
        session.swipe(.again)
        #expect(session.isFinished)
        #expect(session.reviewedCount == 1)
    }

    @Test func canFocusOnOneCategory() {
        let work = library.createCategory(name: "Work")
        let a = library.add(kind: .review, title: "a", categoryIDs: [work.id])
        library.add(kind: .review, title: "b")
        let session = ReviewSession(library: library, categoryID: work.id)
        #expect(session.queue.map(\.id) == [a.id])
    }

    @Test func browseModeShowsEverythingWithoutRescheduling() {
        let a = library.add(kind: .review, title: "a")
        library.grade(a.id, .gotIt)
        let session = ReviewSession(library: library, mode: .browseAll)
        #expect(session.queue.map(\.id) == [a.id])
        let before = library.item(a.id)?.review
        session.swipe(.gotIt)
        #expect(library.item(a.id)?.review == before)
    }

    @Test func undoBringsBackTheLastCardAndRestoresItsSchedule() {
        let a = library.add(kind: .review, title: "a")
        let before = library.item(a.id)?.review
        let session = ReviewSession(library: library)
        session.swipe(.gotIt)
        session.undo()
        #expect(session.current?.id == a.id)
        #expect(library.item(a.id)?.review == before)
    }

    @Test func dueCountsPerCategoryForTheChips() {
        let work = library.createCategory(name: "Work")
        library.add(kind: .review, title: "a", categoryIDs: [work.id])
        library.add(kind: .review, title: "b", categoryIDs: [work.id])
        library.add(kind: .review, title: "c")
        let counts = ReviewSession.dueCounts(in: library)
        #expect(counts.total == 3)
        #expect(counts.byCategory[work.id] == 2)
    }

    @Test func previewOfNextGap() {
        library.add(kind: .review, title: "a")
        let session = ReviewSession(library: library)
        #expect(session.nextGapDays(for: .gotIt) == 1)
        #expect(session.nextGapDays(for: .again) == 1)
    }
}
