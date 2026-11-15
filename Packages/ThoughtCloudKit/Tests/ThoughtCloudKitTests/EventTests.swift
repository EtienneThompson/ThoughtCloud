import Foundation
import Testing
@testable import ThoughtCloudKit

/// Records calendar calls; can simulate missing permission or failures.
@MainActor
final class SpyCalendar: CalendarSyncing {
    enum Mode { case ok, notAuthorized, failing }
    var mode = Mode.ok
    var saved: [(draft: CalendarEventDraft, existingID: String?)] = []
    var removed: [String] = []
    private var counter = 0

    func save(_ draft: CalendarEventDraft, existingID: String?) throws -> String {
        switch mode {
        case .notAuthorized: throw CalendarSyncError.notAuthorized
        case .failing: throw CocoaError(.fileWriteUnknown)
        case .ok:
            saved.append((draft, existingID))
            if let existingID { return existingID }
            counter += 1
            return "cal-\(counter)"
        }
    }

    func remove(id: String) throws {
        switch mode {
        case .notAuthorized: throw CalendarSyncError.notAuthorized
        case .failing: throw CocoaError(.fileWriteUnknown)
        case .ok: removed.append(id)
        }
    }
}

@Suite("Event review scheduler")
struct EventReviewSchedulerTests {
    let scheduler = EventReviewScheduler(calendar: .testUTC)
    /// Event on Nov 30 at 19:00.
    let event = EventInfo(start: day(30, hour: 19), end: day(30, hour: 20), isAllDay: false)

    @Test func farAwayEventFirstComesUpTwoWeeksBefore() {
        let state = scheduler.initialState(for: event, now: day(1, hour: 9))
        #expect(state.nextReviewAt == day(16, hour: 0))
    }

    @Test func eventWithinTwoWeeksIsDueRightAway() {
        let now = day(28, hour: 9)
        let state = scheduler.initialState(for: event, now: now)
        #expect(scheduler.isDue(state, event: event, now: now))
    }

    @Test func gotItWalksTheCheckpointsTowardsTheDay() {
        var state = scheduler.initialState(for: event, now: day(16, hour: 9))
        let expected = [day(23, hour: 0), day(27, hour: 0), day(29, hour: 0), day(30, hour: 0)]
        var now = day(16, hour: 9)
        for next in expected {
            state = scheduler.gotIt(state, event: event, now: now)
            #expect(state.nextReviewAt == next)
            now = next.addingTimeInterval(9 * 3600)
        }
        #expect(state.seenCount == 4)
    }

    @Test func gotItBetweenCheckpointsGoesToTheNextOne() {
        let state = scheduler.initialState(for: event, now: day(25, hour: 9))
        #expect(scheduler.gotIt(state, event: event, now: day(25, hour: 9)).nextReviewAt == day(27, hour: 0))
    }

    @Test func gotItOnTheDayRetiresTheCard() {
        let now = day(30, hour: 8)
        let state = scheduler.gotIt(scheduler.initialState(for: event, now: now), event: event, now: now)
        #expect(state.nextReviewAt == day(1, month: 12, hour: 0))
        #expect(!scheduler.isDue(state, event: event, now: day(1, month: 12, hour: 9)))
    }

    @Test func againMeansTomorrow() {
        let now = day(20, hour: 9)
        let state = scheduler.again(scheduler.initialState(for: event, now: now), now: now)
        #expect(state.nextReviewAt == day(21, hour: 0))
    }

    @Test func expiresTheDayAfterItEnds() {
        let multiDay = EventInfo(start: day(18, hour: 0), end: day(21, hour: 0), isAllDay: true)
        #expect(!scheduler.isExpired(multiDay, now: day(21, hour: 23)))
        #expect(scheduler.isExpired(multiDay, now: day(22, hour: 0)))
    }

    @Test func gapDaysForTheButtons() {
        let now = day(25, hour: 9)
        let state = scheduler.initialState(for: event, now: now)
        #expect(scheduler.daysUntilNextReview(afterGotIt: state, event: event, now: now) == 2)
        #expect(scheduler.daysUntilNextReview(afterAgain: state, now: now) == 1)
    }
}

@Suite("Event info")
struct EventInfoTests {
    @Test func timedDateLastsAnHour() {
        let info = EventInfo.make(from: DetectedDate(date: day(14, hour: 19), hasTime: true, matchedText: ""), now: day(10), calendar: .testUTC)
        #expect(info.start == day(14, hour: 19))
        #expect(info.end == day(14, hour: 20))
        #expect(!info.isAllDay)
    }

    @Test func dateWithoutTimeIsAllDay() {
        let info = EventInfo.make(from: DetectedDate(date: day(14, hour: 12), hasTime: false, matchedText: ""), now: day(10), calendar: .testUTC)
        #expect(info.start == day(14, hour: 0))
        #expect(info.isAllDay)
    }

    @Test func noDateMeansAllDayToday() {
        let info = EventInfo.make(from: nil, now: day(10, hour: 15), calendar: .testUTC)
        #expect(info.start == day(10, hour: 0))
        #expect(info.isAllDay)
    }
}

@MainActor
@Suite("Library events")
struct LibraryEventTests {
    let clock = FakeClock(day(10, hour: 9))
    let persistence = SpyPersistence()
    let calendarSpy = SpyCalendar()
    let library: Library
    let sat7pm = DetectedDate(date: day(14, hour: 19), hasTime: true, matchedText: "Sat at 7pm")

    init() {
        library = Library(persistence: persistence, dates: clock, calendar: .testUTC, calendarSync: calendarSpy)
    }

    @Test func addingAnEventAddsItToTheCalendarAndRemembersTheID() throws {
        let item = library.add(kind: .event, title: "Sam's birthday dinner", body: "Where: Lupa", date: sat7pm)
        let stored = try #require(library.item(item.id))
        #expect(stored.event?.start == day(14, hour: 19))
        #expect(stored.event?.calendarEventID == "cal-1")
        #expect(calendarSpy.saved.first?.draft == CalendarEventDraft(title: "Sam's birthday dinner", notes: "Where: Lupa", start: day(14, hour: 19), end: day(14, hour: 20), isAllDay: false))
        #expect(persistence.stored.items.first?.event?.calendarEventID == "cal-1")
    }

    @Test func eventsCanSkipTheCalendar() {
        let item = library.add(kind: .event, title: "Private thing", date: sat7pm, addToCalendar: false)
        #expect(calendarSpy.saved.isEmpty)
        #expect(library.item(item.id)?.event?.addToCalendar == false)
    }

    @Test func nearEventsAreDueInReviewAlongsideCards() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        let card = library.add(kind: .review, title: "Priya")
        #expect(Set(library.dueReviews().map(\.id)) == [event.id, card.id])
    }

    @Test func farEventsAreNotDueYet() {
        library.add(kind: .event, title: "Flight", date: DetectedDate(date: day(20, month: 12), hasTime: true, matchedText: ""))
        #expect(library.dueReviews().isEmpty)
    }

    @Test func gradingAnEventUsesTheEventCheckpoints() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        library.grade(event.id, .gotIt)
        // Nov 14 event, today Nov 10 → next checkpoint is 3 days before (Nov 11).
        #expect(library.item(event.id)?.review?.nextReviewAt == day(11, hour: 0))
        #expect(library.nextReviewGapDays(for: event.id, .gotIt) == 1)
    }

    @Test func gotItOnTheDayOfAnEventRetiresIt() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        #expect(!library.retiresAfterGotIt(event.id))
        clock.current = day(14, hour: 9)
        #expect(library.retiresAfterGotIt(event.id))
        let card = library.add(kind: .review, title: "Priya")
        #expect(!library.retiresAfterGotIt(card.id))
    }

    @Test func editingTheTextUpdatesTheCalendarEvent() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        library.updateText(event.id, title: "Birthday dinner", body: "")
        #expect(calendarSpy.saved.last?.existingID == "cal-1")
        #expect(calendarSpy.saved.last?.draft.title == "Birthday dinner")
    }

    @Test func changingTimesUpdatesTheCalendarAndTheSchedule() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        library.setEventTimes(event.id, start: day(15, month: 12, hour: 18), end: day(15, month: 12, hour: 21), isAllDay: false)
        let item = library.item(event.id)
        #expect(item?.event?.end == day(15, month: 12, hour: 21))
        #expect(calendarSpy.saved.last?.draft.start == day(15, month: 12, hour: 18))
        #expect(library.dueReviews().isEmpty)
    }

    @Test func endIsNeverBeforeStart() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        library.setEventTimes(event.id, start: day(14, hour: 19), end: day(14, hour: 18), isAllDay: false)
        #expect(library.item(event.id)?.event?.end == day(14, hour: 19))
    }

    @Test func deletingAnEventRemovesItFromTheCalendar() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        library.delete(event.id)
        #expect(calendarSpy.removed == ["cal-1"])
    }

    @Test func turningCalendarOffRemovesItAndOnAddsItBack() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        library.setAddToCalendar(event.id, false)
        #expect(calendarSpy.removed == ["cal-1"])
        #expect(library.item(event.id)?.event?.calendarEventID == nil)
        library.setAddToCalendar(event.id, true)
        #expect(library.item(event.id)?.event?.calendarEventID == "cal-2")
    }

    @Test func changingKindAwayFromEventRemovesTheCalendarEntry() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        library.setKind(event.id, .todo)
        #expect(calendarSpy.removed == ["cal-1"])
        #expect(library.item(event.id)?.event?.calendarEventID == nil)
    }

    @Test func turningATodoIntoAnEventUsesItsDueDate() {
        let todo = library.add(kind: .todo, title: "Dinner", date: sat7pm)
        library.setKind(todo.id, .event)
        let item = library.item(todo.id)
        #expect(item?.event?.start == day(14, hour: 19))
        #expect(item?.event?.calendarEventID == "cal-1")
        #expect(item?.review != nil)
    }

    @Test func promotingAThoughtToAnEventMakesAnAllDayEventToday() {
        let thought = library.add(kind: .thought, title: "Picnic")
        let event = library.promote(thought.id, to: .event)
        #expect(event?.event?.isAllDay == true)
        #expect(library.item(event!.id)?.event?.calendarEventID == "cal-1")
    }

    @Test func eventsArchiveTheDayAfterTheyEnd() {
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        clock.current = day(15, hour: 1)
        library.refresh()
        #expect(library.item(event.id)?.isArchived == true)
        #expect(calendarSpy.removed.isEmpty)
    }

    @Test func missingPermissionIsQuietAndRetriedLater() {
        calendarSpy.mode = .notAuthorized
        let event = library.add(kind: .event, title: "Dinner", date: sat7pm)
        #expect(library.lastError == nil)
        #expect(library.item(event.id)?.event?.calendarEventID == nil)
        calendarSpy.mode = .ok
        library.syncPendingCalendarEvents()
        #expect(library.item(event.id)?.event?.calendarEventID == "cal-1")
    }

    @Test func otherCalendarErrorsAreSurfaced() {
        calendarSpy.mode = .failing
        library.add(kind: .event, title: "Dinner", date: sat7pm)
        #expect(library.lastError != nil)
    }

    @Test func upcomingEventsAreSortedByStart() {
        let later = library.add(kind: .event, title: "Later", date: DetectedDate(date: day(20), hasTime: false, matchedText: ""))
        let sooner = library.add(kind: .event, title: "Sooner", date: sat7pm)
        #expect(library.upcomingEvents().map(\.id) == [sooner.id, later.id])
    }

    @Test func eventsWithoutTheFieldStillDecode() throws {
        let json = #"{"schemaVersion":1,"items":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"thought","title":"Old","body":"","categoryIDs":[],"createdAt":"2026-11-01T09:00:00Z","updatedAt":"2026-11-01T09:00:00Z","dueHasTime":false}],"categories":[],"links":[]}"#
        let snapshot = try JSONDecoder.library.decode(LibrarySnapshot.self, from: Data(json.utf8))
        #expect(snapshot.items.first?.event == nil)
    }
}

@Suite("Event sectioner")
struct EventSectionerTests {
    let sectioner = EventSectioner(calendar: .testUTC)
    let now = day(12, hour: 9) // Thursday Nov 12

    func event(_ title: String, _ start: Date, end: Date? = nil) -> Item {
        var item = Item(kind: .event, title: title, createdAt: day(1))
        item.event = EventInfo(start: start, end: end ?? start.addingTimeInterval(3600), isAllDay: false)
        return item
    }

    @Test func groupsIntoThisWeekLaterThisMonthAndMonths() {
        let items = [
            event("Flight", day(26, hour: 8)),
            event("Dinner", day(14, hour: 19)),
            event("Review", day(1, month: 12, hour: 14)),
            event("New year", day(2, month: 1, year: 2027, hour: 10)),
            event("Dentist", day(16, hour: 10)),
        ]
        let groups = sectioner.sections(for: items, now: now)
        #expect(groups.map(\.section) == [.thisWeek, .laterThisMonth, .month(year: 2026, month: 12), .month(year: 2027, month: 1)])
        #expect(groups[0].items.map(\.title) == ["Dinner", "Dentist"])
    }

    @Test func eventsHappeningNowOrEarlierTodayCountAsThisWeek() {
        let groups = sectioner.sections(for: [event("Offsite", day(12, hour: 8), end: day(12, hour: 17))], now: now)
        #expect(groups.map(\.section) == [.thisWeek])
    }

    @Test func daysUntilIsCountedInCalendarDays() {
        #expect(sectioner.daysUntil(event("Dinner", day(14, hour: 19)), now: now) == 2)
        #expect(sectioner.daysUntil(event("Offsite", day(12, hour: 8)), now: now) == 0)
    }
}

@Suite("Capture parser · events")
struct CaptureParserEventTests {
    @Test func aDateWithATimeIsAnEvent() {
        let parser = CaptureParser(dateDetector: FakeDateDetector(trigger: "Sat", result: DetectedDate(date: day(14, hour: 19), hasTime: true, matchedText: "Sat at 7pm")))
        #expect(parser.parse("Sam's birthday dinner Sat at 7pm").suggestedKind == .event)
    }

    @Test func aDateWithoutATimeIsStillAReview() {
        let parser = CaptureParser(dateDetector: FakeDateDetector(trigger: "March", result: DetectedDate(date: day(14, month: 3, year: 2027), hasTime: false, matchedText: "March 14")))
        #expect(parser.parse("Sam's birthday is March 14").suggestedKind == .review)
    }

    @Test func eventPrefixForcesAnEvent() {
        let parser = CaptureParser(dateDetector: FakeDateDetector.none)
        let draft = parser.parse("event: Mom visits")
        #expect(draft.suggestedKind == .event)
        #expect(draft.title == "Mom visits")
    }
}

@MainActor
@Suite("Capture model · events")
struct CaptureModelEventTests {
    let clock = FakeClock(day(10, hour: 9))
    let calendarSpy = SpyCalendar()
    let library: Library
    let model: CaptureModel

    init() {
        library = Library(persistence: SpyPersistence(), dates: clock, calendar: .testUTC, calendarSync: calendarSpy)
        model = CaptureModel(library: library, parser: CaptureParser(dateDetector: FakeDateDetector(
            trigger: "Sat", result: DetectedDate(date: day(14, hour: 19), hasTime: true, matchedText: "Sat at 7pm"))))
    }

    @Test func showsTheEventTimesItWillSave() {
        model.text = "Dinner Sat at 7pm"
        #expect(model.kind == .event)
        #expect(model.eventPreview == EventInfo(start: day(14, hour: 19), end: day(14, hour: 20), isAllDay: false))
    }

    @Test func calendarIsOnByDefaultAndCanBeTurnedOffForOneEvent() throws {
        model.text = "Dinner Sat at 7pm"
        #expect(model.addToCalendar)
        model.addToCalendar = false
        let item = try #require(model.save())
        #expect(item.event?.addToCalendar == false)
        #expect(calendarSpy.saved.isEmpty)
        #expect(model.addToCalendar)
    }

    @Test func nonEventsHaveNoEventPreview() {
        model.text = "Just a thought"
        #expect(model.eventPreview == nil)
    }
}

@MainActor
@Suite("Review session · events")
struct ReviewSessionEventTests {
    @Test func browseAllIncludesEventsAndGapsUseEventCheckpoints() {
        let clock = FakeClock(day(10, hour: 9))
        let library = Library(persistence: SpyPersistence(), dates: clock, calendar: .testUTC, calendarSync: SpyCalendar())
        let event = library.add(kind: .event, title: "Dinner", date: DetectedDate(date: day(14, hour: 19), hasTime: true, matchedText: ""))
        let session = ReviewSession(library: library)
        #expect(session.current?.id == event.id)
        #expect(session.nextGapDays(for: .gotIt) == 1)
        #expect(ReviewSession(library: library, mode: .browseAll).queue.map(\.id) == [event.id])
    }
}

@MainActor
@Suite("Graph · events")
struct GraphEventTests {
    @Test func dueEventsPulseLikeDueCards() {
        let library = Library(persistence: SpyPersistence(), dates: FakeClock(day(10, hour: 9)), calendar: .testUTC)
        let event = library.add(kind: .event, title: "Dinner", date: DetectedDate(date: day(14, hour: 19), hasTime: true, matchedText: ""))
        let node = GraphBuilder.build(from: library).nodes.first { $0.id == .item(event.id) }
        #expect(node?.isDue == true)
    }
}
