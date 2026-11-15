import Foundation
import Testing
@testable import ThoughtCloudKit

final class FakeClock: DateProviding, @unchecked Sendable {
    var current: Date
    init(_ current: Date) { self.current = current }
    func now() -> Date { current }
}

final class SpyPersistence: LibraryPersisting, @unchecked Sendable {
    var stored: LibrarySnapshot
    var saveCount = 0
    var failSaves = false
    init(_ initial: LibrarySnapshot = .empty) { stored = initial }

    func load() throws -> LibrarySnapshot { stored }
    func save(_ snapshot: LibrarySnapshot) throws {
        if failSaves { throw CocoaError(.fileWriteNoPermission) }
        saveCount += 1
        stored = snapshot
    }
}

@MainActor
@Suite("Library")
struct LibraryTests {
    let clock = FakeClock(day(10, hour: 9))
    let persistence = SpyPersistence()
    let library: Library

    init() {
        library = Library(persistence: persistence, dates: clock, calendar: .testUTC)
    }

    // MARK: Adding

    @Test func addingATodoUsesTheDetectedDateAsDueDate() {
        let item = library.add(kind: .todo, title: "Call dentist", date: DetectedDate(date: day(11, hour: 10), hasTime: true, matchedText: "tomorrow at 10"))
        #expect(item.dueDate == day(11, hour: 10))
        #expect(item.dueHasTime)
        #expect(library.items == [item])
    }

    @Test func addingAReviewUsesTheDetectedDateAsRememberUntilAndIsDueNow() {
        let item = library.add(kind: .review, title: "Mom lands Thursday", date: DetectedDate(date: day(12), hasTime: true, matchedText: "Thursday"))
        #expect(item.review?.rememberUntil == day(12))
        #expect(item.dueDate == nil)
        #expect(library.dueReviews().map(\.id) == [item.id])
    }

    @Test func addingAThoughtIgnoresDates() {
        let item = library.add(kind: .thought, title: "Idea", date: DetectedDate(date: day(12), hasTime: false, matchedText: "x"))
        #expect(item.dueDate == nil && item.review == nil)
    }

    @Test func everyChangeIsPersisted() {
        library.add(kind: .thought, title: "One")
        library.add(kind: .thought, title: "Two")
        #expect(persistence.saveCount == 2)
        #expect(persistence.stored.items.count == 2)
    }

    @Test func loadsWhatWasPersistedBefore() {
        let item = Item(kind: .thought, title: "Persisted", createdAt: day(1))
        let library = Library(persistence: SpyPersistence(LibrarySnapshot(items: [item])), dates: clock, calendar: .testUTC)
        #expect(library.items.map(\.title) == ["Persisted"])
    }

    @Test func saveFailuresAreSurfacedNotSwallowed() {
        persistence.failSaves = true
        library.add(kind: .thought, title: "x")
        #expect(library.lastError != nil)
        #expect(library.items.count == 1)
    }

    // MARK: Categories

    @Test func hashtagsResolveToExistingCategoriesOrCreateNewOnes() {
        let work = library.createCategory(name: "Work")
        let ids = library.categoryIDs(forHashtags: ["WORK", "side-projects"])
        #expect(ids.first == work.id)
        #expect(library.categories.map(\.name) == ["Work", "Side Projects"])
        #expect(ids.count == 2)
    }

    @Test func newCategoriesGetDistinctPaletteColors() {
        let a = library.createCategory(name: "A")
        let b = library.createCategory(name: "B")
        #expect(a.colorHex != b.colorHex)
    }

    @Test func creatingADuplicateNameReturnsTheExistingCategory() {
        let a = library.createCategory(name: "Work")
        let b = library.createCategory(name: "work")
        #expect(a.id == b.id)
        #expect(library.categories.count == 1)
    }

    @Test func deletingACategoryRemovesItFromItems() {
        let work = library.createCategory(name: "Work")
        let item = library.add(kind: .thought, title: "x", categoryIDs: [work.id])
        library.deleteCategory(work.id)
        #expect(library.item(item.id)?.categoryIDs == [])
        #expect(library.categories.isEmpty)
    }

    @Test func seedsDefaultCategoriesOnlyIntoAnEmptyLibrary() {
        library.seedDefaultCategoriesIfNeeded()
        let count = library.categories.count
        #expect(count > 0)
        library.seedDefaultCategoriesIfNeeded()
        #expect(library.categories.count == count)
    }

    @Test func itemsInCategoryIncludeMultiCategoryItems() {
        let work = library.createCategory(name: "Work")
        let travel = library.createCategory(name: "Travel")
        let both = library.add(kind: .todo, title: "Book flights", categoryIDs: [travel.id, work.id])
        #expect(library.items(inCategory: work.id).map(\.id) == [both.id])
        #expect(library.items(inCategory: travel.id).map(\.id) == [both.id])
    }

    // MARK: Todos

    @Test func togglingCompletesAndReopens() {
        let item = library.add(kind: .todo, title: "x")
        library.toggleCompleted(item.id)
        #expect(library.item(item.id)?.completedAt == clock.current)
        library.toggleCompleted(item.id)
        #expect(library.item(item.id)?.isCompleted == false)
    }

    // MARK: Review

    @Test func gradingGotItPushesTheCardOut() {
        let item = library.add(kind: .review, title: "fact")
        library.grade(item.id, .gotIt)
        #expect(library.item(item.id)?.review?.nextReviewAt == day(11, hour: 0))
        #expect(library.dueReviews().isEmpty)
    }

    @Test func dueReviewsCanBeFilteredByCategory() {
        let work = library.createCategory(name: "Work")
        let a = library.add(kind: .review, title: "a", categoryIDs: [work.id])
        library.add(kind: .review, title: "b")
        #expect(library.dueReviews(inCategory: work.id).map(\.id) == [a.id])
    }

    @Test func expiredReviewsAreArchivedAutomatically() {
        let item = library.add(kind: .review, title: "dentist", date: DetectedDate(date: day(12), hasTime: false, matchedText: ""))
        clock.current = day(13, hour: 8)
        library.refresh()
        #expect(library.item(item.id)?.isArchived == true)
        #expect(library.dueReviews().isEmpty)
    }

    @Test func settingRememberUntilOnAnExistingCard() {
        let item = library.add(kind: .review, title: "x")
        library.setRememberUntil(item.id, day(20))
        #expect(library.item(item.id)?.review?.rememberUntil == day(20))
    }

    // MARK: Editing

    @Test func changingKindToReviewMakesTheItemDue() {
        let item = library.add(kind: .thought, title: "x")
        library.setKind(item.id, .review)
        #expect(library.dueReviews().map(\.id) == [item.id])
    }

    @Test func editingTextUpdatesTimestamp() {
        let item = library.add(kind: .thought, title: "x")
        clock.current = day(11)
        library.updateText(item.id, title: "y", body: "z")
        let updated = library.item(item.id)
        #expect(updated?.title == "y" && updated?.body == "z")
        #expect(updated?.updatedAt == day(11))
    }

    // MARK: Links & promotion

    @Test func promotingAThoughtCreatesALinkedItemAndKeepsTheThought() {
        let work = library.createCategory(name: "Work")
        let thought = library.add(kind: .thought, title: "Async standup?", body: "maybe fridays", categoryIDs: [work.id])
        let todo = library.promote(thought.id, to: .todo)
        #expect(todo?.kind == .todo)
        #expect(todo?.title == "Async standup?")
        #expect(todo?.categoryIDs == [work.id])
        #expect(library.item(thought.id) != nil)
        #expect(library.linkedItems(of: thought.id).map(\.id) == [todo!.id])
        #expect(library.links.first?.kind == .promoted)
    }

    @Test func linksAreUndirectedAndNotDuplicated() {
        let a = library.add(kind: .thought, title: "a")
        let b = library.add(kind: .thought, title: "b")
        library.link(a.id, b.id)
        library.link(b.id, a.id)
        library.link(a.id, a.id)
        #expect(library.links.count == 1)
        #expect(library.linkedItems(of: b.id).map(\.id) == [a.id])
        library.unlink(b.id, a.id)
        #expect(library.links.isEmpty)
    }

    @Test func deletingAnItemRemovesItsLinks() {
        let a = library.add(kind: .thought, title: "a")
        let b = library.add(kind: .thought, title: "b")
        library.link(a.id, b.id)
        library.delete(a.id)
        #expect(library.links.isEmpty)
        #expect(library.items.map(\.id) == [b.id])
    }

    @Test func exportProducesDecodableJSON() throws {
        library.add(kind: .thought, title: "a")
        let decoded = try JSONDecoder.library.decode(LibrarySnapshot.self, from: library.exportData())
        #expect(decoded.items.map(\.title) == ["a"])
    }
}

@Suite("JSON file persistence")
struct JSONFilePersistenceTests {
    func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tc-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func missingFileLoadsAsEmpty() throws {
        let store = JSONFilePersistence(directory: try tempDirectory())
        #expect(try store.load() == .empty)
    }

    @Test func savesAndLoads() throws {
        let store = JSONFilePersistence(directory: try tempDirectory())
        let snapshot = LibrarySnapshot(items: [Item(kind: .thought, title: "x", createdAt: day(1))])
        try store.save(snapshot)
        #expect(try store.load() == snapshot)
    }

    @Test func corruptFileIsQuarantinedNotOverwritten() throws {
        let dir = try tempDirectory()
        let store = JSONFilePersistence(directory: dir)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: PersistenceError.self) { try store.load() }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("library-corrupt-") })
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func keepsABackupOfThePreviousVersion() throws {
        let store = JSONFilePersistence(directory: try tempDirectory())
        try store.save(LibrarySnapshot(items: [Item(kind: .thought, title: "v1", createdAt: day(1))]))
        try store.save(LibrarySnapshot(items: [Item(kind: .thought, title: "v2", createdAt: day(1))]))
        let backup = try JSONDecoder.library.decode(LibrarySnapshot.self, from: Data(contentsOf: store.backupURL))
        #expect(backup.items.map(\.title) == ["v1"])
    }
}
