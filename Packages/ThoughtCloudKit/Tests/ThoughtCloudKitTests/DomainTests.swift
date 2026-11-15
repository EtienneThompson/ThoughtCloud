import Foundation
import Testing
@testable import ThoughtCloudKit

@Suite("Domain model")
struct DomainTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func snapshotRoundTripsThroughJSON() throws {
        let work = ItemCategory(name: "Work", emoji: "💼", colorHex: "#64D2FF", createdAt: now)
        var item = Item(kind: .review, title: "Lisbon trip", body: "- Dec 18: TP 214", createdAt: now)
        item.categoryIDs = [work.id]
        item.review = ReviewState(nextReviewAt: now, rememberUntil: now.addingTimeInterval(86_400))
        let link = ItemLink(from: item.id, to: UUID(), kind: .manual, createdAt: now)
        let snapshot = LibrarySnapshot(items: [item], categories: [work], links: [link])

        let data = try JSONEncoder.library.encode(snapshot)
        let decoded = try JSONDecoder.library.decode(LibrarySnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.schemaVersion == LibrarySnapshot.currentSchemaVersion)
    }

    @Test func changingKindToReviewCreatesReviewStateDueNow() {
        var item = Item(kind: .thought, title: "Idea", createdAt: now)
        item.changeKind(to: .review, now: now)
        #expect(item.kind == .review)
        #expect(item.review?.nextReviewAt == now)
        #expect(item.review?.seenCount == 0)
    }

    @Test func changingKindAwayFromTodoClearsCompletion() {
        var item = Item(kind: .todo, title: "Call", createdAt: now)
        item.completedAt = now
        item.changeKind(to: .thought, now: now)
        #expect(item.completedAt == nil)
        #expect(item.isCompleted == false)
    }

    @Test func changingKindKeepsExistingReviewHistoryWhenReturningToReview() {
        var item = Item(kind: .review, title: "Fact", createdAt: now)
        item.review = ReviewState(step: 3, nextReviewAt: now.addingTimeInterval(1000), seenCount: 4)
        item.changeKind(to: .todo, now: now)
        item.changeKind(to: .review, now: now)
        #expect(item.review?.seenCount == 4)
    }

    @Test func emptyTitleFallsBackToBodyFirstLineForDisplay() {
        let item = Item(kind: .thought, title: "  ", body: "first line\nsecond", createdAt: now)
        #expect(item.displayTitle == "first line")
    }
}
