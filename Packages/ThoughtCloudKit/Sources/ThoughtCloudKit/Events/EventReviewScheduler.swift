import Foundation

/// Events come up more often as they get closer: two weeks, one week, three
/// days and one day before, then on the day. They retire the day after they end.
public struct EventReviewScheduler: Sendable {
    public static let defaultCheckpoints = [14, 7, 3, 1, 0]

    public let checkpoints: [Int]
    public let calendar: Calendar

    public init(checkpoints: [Int] = EventReviewScheduler.defaultCheckpoints, calendar: Calendar = .current) {
        self.checkpoints = checkpoints.sorted(by: >)
        self.calendar = calendar
    }

    public func initialState(for event: EventInfo, now: Date) -> ReviewState {
        let first = checkpointDates(for: event).first ?? eventDay(event)
        return ReviewState(nextReviewAt: first <= now ? now : first)
    }

    public func isDue(_ state: ReviewState, event: EventInfo, now: Date) -> Bool {
        state.nextReviewAt <= now && !isExpired(event, now: now)
    }

    public func isExpired(_ event: EventInfo, now: Date) -> Bool {
        now >= adding(days: 1, to: calendar.startOfDay(for: event.end))
    }

    public func gotIt(_ state: ReviewState, event: EventInfo, now: Date) -> ReviewState {
        var next = state
        let today = calendar.startOfDay(for: now)
        next.nextReviewAt = checkpointDates(for: event).first { $0 > today }
            ?? adding(days: 1, to: calendar.startOfDay(for: event.end))
        next.seenCount += 1
        next.lastReviewedAt = now
        return next
    }

    public func again(_ state: ReviewState, now: Date) -> ReviewState {
        var next = state
        next.nextReviewAt = adding(days: 1, to: calendar.startOfDay(for: now))
        next.seenCount += 1
        next.lastReviewedAt = now
        return next
    }

    public func daysUntilNextReview(afterGotIt state: ReviewState, event: EventInfo, now: Date) -> Int {
        days(from: now, to: gotIt(state, event: event, now: now).nextReviewAt)
    }

    public func daysUntilNextReview(afterAgain state: ReviewState, now: Date) -> Int {
        days(from: now, to: again(state, now: now).nextReviewAt)
    }

    // MARK: - Helpers

    private func eventDay(_ event: EventInfo) -> Date { calendar.startOfDay(for: event.start) }

    /// Checkpoint days, earliest first.
    private func checkpointDates(for event: EventInfo) -> [Date] {
        checkpoints.map { adding(days: -$0, to: eventDay(event)) }
    }

    private func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    private func days(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }
}
