import Foundation
import Observation

/// One pass through a stack of review cards. The queue is captured up front
/// so cards don't reshuffle while you swipe.
@MainActor
@Observable
public final class ReviewSession {
    public enum Mode: Sendable {
        /// Only cards that are due; swipes reschedule.
        case due
        /// Every active card; swipes just move on (practice without affecting the schedule).
        case browseAll
    }

    public let mode: Mode
    public let categoryID: UUID?
    public private(set) var queue: [Item]
    public private(set) var index = 0

    @ObservationIgnored private let library: Library
    @ObservationIgnored private var history: [(id: UUID, previous: ReviewState?)] = []

    public init(library: Library, categoryID: UUID? = nil, mode: Mode = .due) {
        self.library = library
        self.categoryID = categoryID
        self.mode = mode
        switch mode {
        case .due:
            queue = library.dueReviews(inCategory: categoryID)
        case .browseAll:
            queue = library.reviewableItems(inCategory: categoryID)
        }
    }

    public var current: Item? {
        guard queue.indices.contains(index) else { return nil }
        return library.item(queue[index].id) ?? queue[index]
    }

    /// Cards after the current one (for drawing the stack underneath).
    public func upcoming(_ count: Int) -> [Item] {
        let start = index + 1
        guard start < queue.count else { return [] }
        return queue[start..<min(queue.count, start + count)].map { library.item($0.id) ?? $0 }
    }

    public var remaining: Int { max(0, queue.count - index) }
    public var reviewedCount: Int { index }
    public var isFinished: Bool { index >= queue.count }

    public func swipe(_ grade: ReviewGrade) {
        guard let item = current else { return }
        history.append((item.id, item.review))
        if mode == .due { library.grade(item.id, grade) }
        index += 1
    }

    public var canUndo: Bool { !history.isEmpty }

    public func undo() {
        guard let last = history.popLast() else { return }
        if mode == .due { library.setReviewState(last.id, last.previous) }
        index = max(0, index - 1)
    }

    public func nextGapDays(for grade: ReviewGrade) -> Int? {
        guard let item = current else { return nil }
        return library.nextReviewGapDays(for: item.id, grade)
    }

    public static func dueCounts(in library: Library) -> (total: Int, byCategory: [UUID: Int]) {
        let due = library.dueReviews()
        var byCategory: [UUID: Int] = [:]
        for item in due {
            for id in item.categoryIDs { byCategory[id, default: 0] += 1 }
        }
        return (due.count, byCategory)
    }
}
