import Foundation

/// Spaced repetition without questions: "got it" pushes a card further out,
/// "again" brings it back tomorrow. An optional remember-until date caps gaps
/// (half the remaining time) and retires the card once that day has passed.
public struct ReviewScheduler: Sendable {
    public static let defaultIntervals = [1, 3, 7, 14, 30, 60]

    public let intervals: [Int]
    public let calendar: Calendar

    public init(intervals: [Int] = ReviewScheduler.defaultIntervals, calendar: Calendar = .current) {
        precondition(!intervals.isEmpty, "Need at least one interval")
        self.intervals = intervals
        self.calendar = calendar
    }

    public func initialState(now: Date, rememberUntil: Date?) -> ReviewState {
        ReviewState(nextReviewAt: now, rememberUntil: rememberUntil)
    }

    public func isDue(_ state: ReviewState, now: Date) -> Bool {
        state.nextReviewAt <= now && !isExpired(state, now: now)
    }

    public func isExpired(_ state: ReviewState, now: Date) -> Bool {
        guard let until = state.rememberUntil else { return false }
        return now >= dayAfter(until)
    }

    public func gotIt(_ state: ReviewState, now: Date) -> ReviewState {
        var next = state
        let today = calendar.startOfDay(for: now)
        let ladderGap = intervals[min(max(state.step, 0), intervals.count - 1)]

        if let until = state.rememberUntil {
            let untilDay = calendar.startOfDay(for: until)
            let remaining = days(from: today, to: untilDay)
            if remaining <= 0 {
                next.nextReviewAt = dayAfter(until)
            } else {
                let gap = min(ladderGap, max(1, remaining / 2))
                next.nextReviewAt = min(adding(days: gap, to: today), untilDay)
            }
        } else {
            next.nextReviewAt = adding(days: ladderGap, to: today)
        }

        next.step = min(state.step + 1, intervals.count - 1)
        next.seenCount += 1
        next.lastReviewedAt = now
        return next
    }

    public func again(_ state: ReviewState, now: Date) -> ReviewState {
        var next = state
        next.step = 0
        next.nextReviewAt = adding(days: 1, to: calendar.startOfDay(for: now))
        next.seenCount += 1
        next.lastReviewedAt = now
        return next
    }

    public func daysUntilNextReview(afterGotIt state: ReviewState, now: Date) -> Int {
        days(from: calendar.startOfDay(for: now), to: gotIt(state, now: now).nextReviewAt)
    }

    public func daysUntilNextReview(afterAgain state: ReviewState, now: Date) -> Int {
        days(from: calendar.startOfDay(for: now), to: again(state, now: now).nextReviewAt)
    }

    // MARK: - Helpers

    private func dayAfter(_ date: Date) -> Date {
        adding(days: 1, to: calendar.startOfDay(for: date))
    }

    private func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    private func days(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }
}
