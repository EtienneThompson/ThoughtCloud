import Foundation
import Testing
@testable import ThoughtCloudKit

extension Calendar {
    static var testUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

/// Builds dates in UTC: `day(10, hour: 9)` = 2026-11-10 09:00Z.
func day(_ d: Int, month: Int = 11, year: Int = 2026, hour: Int = 9, minute: Int = 0) -> Date {
    Calendar.testUTC.date(from: DateComponents(year: year, month: month, day: d, hour: hour, minute: minute))!
}

@Suite("Review scheduler")
struct ReviewSchedulerTests {
    let scheduler = ReviewScheduler(calendar: .testUTC)

    @Test func newCardIsDueImmediately() {
        let state = scheduler.initialState(now: day(10), rememberUntil: nil)
        #expect(scheduler.isDue(state, now: day(10)))
    }

    @Test func gotItWalksTheIntervalLadder() {
        var state = scheduler.initialState(now: day(1), rememberUntil: nil)
        var now = day(1)
        var gaps: [Int] = []
        for _ in 0..<8 {
            state = scheduler.gotIt(state, now: now)
            let gap = Calendar.testUTC.dateComponents([.day], from: Calendar.testUTC.startOfDay(for: now), to: state.nextReviewAt).day!
            gaps.append(gap)
            now = state.nextReviewAt.addingTimeInterval(3600 * 9)
        }
        #expect(gaps == [1, 3, 7, 14, 30, 60, 60, 60])
        #expect(state.seenCount == 8)
    }

    @Test func nextReviewLandsAtStartOfDaySoItIsDueAllDay() {
        let state = scheduler.gotIt(scheduler.initialState(now: day(10, hour: 22), rememberUntil: nil), now: day(10, hour: 22))
        #expect(state.nextReviewAt == day(11, hour: 0))
    }

    @Test func againResetsToTomorrowAndRestartsLadder() {
        var state = ReviewState(step: 4, nextReviewAt: day(10), seenCount: 6)
        state = scheduler.again(state, now: day(10))
        #expect(state.nextReviewAt == day(11, hour: 0))
        #expect(state.step == 0)
        #expect(state.seenCount == 7)
        state = scheduler.gotIt(state, now: day(11))
        #expect(state.nextReviewAt == day(12, hour: 0))
    }

    @Test func rememberUntilShrinksGapsAsTheDateApproaches() {
        // Card at step 4 (30 days) but the event is 20 days away: gap is capped to half the remaining time.
        let state = ReviewState(step: 4, nextReviewAt: day(1), rememberUntil: day(21, hour: 12))
        let next = scheduler.gotIt(state, now: day(1))
        #expect(next.nextReviewAt == day(11, hour: 0))
    }

    @Test func rememberUntilAlwaysShowsCardOnTheDayItself() {
        // 3 days out: half is 1 day, card comes back tomorrow, then tomorrow again ... and on the day.
        var state = ReviewState(step: 5, nextReviewAt: day(17), rememberUntil: day(20, hour: 12))
        state = scheduler.gotIt(state, now: day(17))
        #expect(state.nextReviewAt == day(18, hour: 0))
        state = scheduler.gotIt(state, now: day(19))
        #expect(state.nextReviewAt == day(20, hour: 0))
    }

    @Test func gotItOnTheFinalDaySchedulesPastTheEndSoItRetires() {
        let state = ReviewState(step: 2, nextReviewAt: day(20), rememberUntil: day(20, hour: 12))
        let next = scheduler.gotIt(state, now: day(20))
        #expect(scheduler.isExpired(next, now: day(21, hour: 1)))
        #expect(!scheduler.isDue(next, now: day(20, hour: 23)))
    }

    @Test func expiresOnlyAfterTheRememberUntilDayEnds() {
        let state = ReviewState(nextReviewAt: day(1), rememberUntil: day(20, hour: 12))
        #expect(!scheduler.isExpired(state, now: day(20, hour: 23, minute: 59)))
        #expect(scheduler.isExpired(state, now: day(21, hour: 0)))
        #expect(!scheduler.isExpired(ReviewState(nextReviewAt: day(1)), now: day(30)))
    }

    @Test func previewDescribesTheNextGapForTheUI() {
        let state = ReviewState(step: 2, nextReviewAt: day(10))
        #expect(scheduler.daysUntilNextReview(afterGotIt: state, now: day(10)) == 7)
        #expect(scheduler.daysUntilNextReview(afterAgain: state, now: day(10)) == 1)
    }
}
