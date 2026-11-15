import Foundation
import Testing
@testable import ThoughtCloudKit

@Suite("Body formatting")
struct BodyFormatterTests {
    @Test func plainTextStaysAsText() {
        #expect(BodyFormatter.blocks(from: "Turning 30. Hates surprises.") == [.text("Turning 30. Hates surprises.")])
    }

    @Test func dashAndBulletLinesBecomeListItems() {
        let blocks = BodyFormatter.blocks(from: "- Respond in 15 min\n* Monday handoff\n• Postmortem")
        #expect(blocks == [.bullet("Respond in 15 min"), .bullet("Monday handoff"), .bullet("Postmortem")])
    }

    @Test func numberedLinesKeepTheirNumber() {
        #expect(BodyFormatter.blocks(from: "1. One\n2) Two") == [.numbered("1", "One"), .numbered("2", "Two")])
    }

    @Test func labelColonValueLinesAreAligned() {
        let blocks = BodyFormatter.blocks(from: "Partner: Dan\nKids: Ava, Leo")
        #expect(blocks == [.labeled("Partner", "Dan"), .labeled("Kids", "Ava, Leo")])
    }

    @Test func listItemsCanCarryLabels() {
        #expect(BodyFormatter.blocks(from: "- Dec 18: TP 214") == [.bullet("Dec 18: TP 214")])
    }

    @Test func timesAndURLsAreNotMistakenForLabels() {
        #expect(BodyFormatter.blocks(from: "Lands at 3:40pm") == [.text("Lands at 3:40pm")])
        #expect(BodyFormatter.blocks(from: "https://example.com") == [.text("https://example.com")])
    }

    @Test func longSentencesWithColonsAreText() {
        let line = "The thing I keep forgetting about the whole plan is this: it works"
        #expect(BodyFormatter.blocks(from: line) == [.text(line)])
    }

    @Test func blankLinesAreDroppedAndWhitespaceTrimmed() {
        #expect(BodyFormatter.blocks(from: "  a  \n\n\n  b ") == [.text("a"), .text("b")])
    }
}

@Suite("ItemCategory style")
struct CategoryStyleTests {
    let now = Date(timeIntervalSince1970: 0)
    var work: ItemCategory { ItemCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Work", emoji: "💼", colorHex: "#64D2FF", createdAt: now) }
    var travel: ItemCategory { ItemCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Travel", emoji: "✈️", colorHex: "#FFD60A", createdAt: now) }
    var home: ItemCategory { ItemCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Home", emoji: "🏠", colorHex: "#30D158", createdAt: now) }
    var all: [ItemCategory] { [work, travel, home] }

    @Test func noCategoriesIsInbox() {
        #expect(CategoryStyle.resolve([], in: all) == .inbox)
    }

    @Test func oneCategoryIsSolid() {
        #expect(CategoryStyle.resolve([work.id], in: all) == .single(work))
    }

    @Test func twoCategoriesKeepPickOrder() {
        #expect(CategoryStyle.resolve([travel.id, work.id], in: all) == .pair(travel, work))
    }

    @Test func threeOrMoreIsMany() {
        #expect(CategoryStyle.resolve([work.id, travel.id, home.id], in: all) == .many([work, travel, home]))
    }

    @Test func unknownIDsAreIgnored() {
        #expect(CategoryStyle.resolve([UUID(), work.id], in: all) == .single(work))
    }

    @Test func colorsExposeWhatToPaint() {
        #expect(CategoryStyle.inbox.colorHexes == [CategoryPalette.inboxHex])
        #expect(CategoryStyle.pair(travel, work).colorHexes == ["#FFD60A", "#64D2FF"])
        #expect(CategoryStyle.many([work, travel, home]).primaryHex == CategoryPalette.manyHex)
        #expect(CategoryStyle.many([work, travel, home]).emojis == "💼✈️🏠")
    }
}

@Suite("Todo sections")
struct TodoSectionsTests {
    let sectioner = TodoSectioner(calendar: .testUTC)
    let now = day(10, hour: 9)

    func todo(_ title: String, due: Date? = nil, done: Date? = nil, created: Date = day(1)) -> Item {
        var item = Item(kind: .todo, title: title, createdAt: created, dueDate: due)
        item.completedAt = done
        return item
    }

    @Test func groupsByDate() {
        let items = [
            todo("overdue", due: day(8)),
            todo("today later", due: day(10, hour: 17)),
            todo("tomorrow", due: day(11)),
            todo("someday"),
            todo("done", done: day(9)),
        ]
        let sections = sectioner.sections(for: items, now: now)
        #expect(sections.map(\.kind) == [.today, .upcoming, .someday, .done])
        #expect(sections[0].items.map(\.title) == ["overdue", "today later"])
        #expect(sections[1].items.map(\.title) == ["tomorrow"])
    }

    @Test func emptySectionsAreOmitted() {
        #expect(sectioner.sections(for: [todo("x")], now: now).map(\.kind) == [.someday])
    }

    @Test func somedayIsNewestFirst() {
        let items = [todo("old", created: day(1)), todo("new", created: day(5))]
        #expect(sectioner.sections(for: items, now: now)[0].items.map(\.title) == ["new", "old"])
    }

    @Test func doneOnlyShowsTheLastWeek() {
        let items = [todo("recent", done: day(5)), todo("ancient", done: day(1, month: 10))]
        #expect(sectioner.sections(for: items, now: now)[0].items.map(\.title) == ["recent"])
    }

    @Test func dateOnlyTodosAreOverdueFromTheNextDay() {
        #expect(sectioner.isOverdue(todo("yesterday", due: day(9)), now: now))
        #expect(!sectioner.isOverdue(todo("today", due: day(10, hour: 0)), now: now))
    }

    @Test func timedTodosAreOverdueOnceTheTimePasses() {
        var passed = todo("8am", due: day(10, hour: 8)); passed.dueHasTime = true
        var later = todo("6pm", due: day(10, hour: 18)); later.dueHasTime = true
        #expect(sectioner.isOverdue(passed, now: now))
        #expect(!sectioner.isOverdue(later, now: now))
    }

    @Test func completedTodosAreNeverOverdue() {
        #expect(!sectioner.isOverdue(todo("d", due: day(9), done: day(9)), now: now))
    }
}
