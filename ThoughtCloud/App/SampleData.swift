#if DEBUG
import Foundation
import ThoughtCloudKit

/// Demo content for previews and simulator screenshots (`-tcSampleData`).
enum SampleData {
    @MainActor
    static func populate(_ library: Library) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func days(_ n: Int, hour: Int = 9) -> Date { cal.date(byAdding: .day, value: n, to: today)!.addingTimeInterval(Double(hour) * 3600) }

        let work = library.createCategory(name: "Work", emoji: "💼", colorHex: "#64D2FF")
        let home = library.createCategory(name: "Home", emoji: "🏠", colorHex: "#30D158")
        let health = library.createCategory(name: "Health", emoji: "💪", colorHex: "#FF6482")
        let learning = library.createCategory(name: "Learning", emoji: "📚", colorHex: "#BF5AF2")
        let travel = library.createCategory(name: "Travel", emoji: "✈️", colorHex: "#FFD60A")
        let projects = library.createCategory(name: "Projects", emoji: "🎨", colorHex: "#FF9F0A")

        let deck = library.add(kind: .todo, title: "Send Q4 deck to Priya", categoryIDs: [work.id], date: DetectedDate(date: days(-2), hasTime: false, matchedText: ""))
        let slides = library.add(kind: .todo, title: "Prep slides for the sync", categoryIDs: [work.id], date: DetectedDate(date: days(3), hasTime: false, matchedText: ""))
        library.add(kind: .todo, title: "Book 1:1 with Alex", categoryIDs: [work.id])
        let standup = library.add(kind: .thought, title: "What if standup was async on Fridays?", categoryIDs: [work.id])
        let dashboard = library.add(kind: .thought, title: "On-call load dashboard per person", categoryIDs: [work.id])
        let oncall = library.add(kind: .review, title: "On-call policy", body: "1. Primary responds within 15 min\n2. Handoff doc every Monday\n3. Any page > 2h gets a postmortem", categoryIDs: [work.id])
        library.add(kind: .review, title: "Priya", body: "Team: 6 people, Berlin\nPartner: Dan\nKids: Ava (6), Leo (3)", categoryIDs: [work.id])

        let flights = library.add(kind: .todo, title: "Book flights for December", categoryIDs: [travel.id, home.id], date: DetectedDate(date: days(2), hasTime: false, matchedText: ""))
        let trip = library.add(kind: .review, title: "Lisbon trip", body: "- Dec 18: TP 214 · JFK 07:40 → LIS\n- Dec 18: Casa Amora, check-in 3pm\n- Dec 21: Train to Porto 09:05\n- Dec 24: Fly home OPO 11:15", categoryIDs: [travel.id], date: DetectedDate(date: days(40), hasTime: false, matchedText: ""))
        library.add(kind: .thought, title: "Pastéis at Manteigaria", categoryIDs: [travel.id])

        let car = library.add(kind: .todo, title: "Renew car registration", categoryIDs: [home.id])
        library.toggleCompleted(car.id)
        library.add(kind: .todo, title: "Fix the squeaky closet door", categoryIDs: [home.id])
        let gift = library.add(kind: .thought, title: "Gift for Sam: ceramic pour-over", categoryIDs: [home.id])
        let bday = library.add(kind: .review, title: "Sam's birthday is March 14", body: "Turning 30. Likes pour-over coffee, hates surprise parties.", categoryIDs: [home.id])

        let dentist = library.add(kind: .todo, title: "Call the dentist about the crown", categoryIDs: [health.id], date: DetectedDate(date: days(0, hour: 10), hasTime: true, matchedText: ""))
        let appt = library.add(kind: .review, title: "Dentist: Thu 10:00", body: "Where: Dr. Okafor, 2nd floor\nBring: Insurance card", categoryIDs: [health.id], date: DetectedDate(date: days(5), hasTime: false, matchedText: ""))
        let sleep = library.add(kind: .thought, title: "Running felt easier after 8h of sleep. Pattern?", categoryIDs: [health.id, learning.id])

        library.add(kind: .todo, title: "SwiftData course ch. 4", categoryIDs: [learning.id], date: DetectedDate(date: days(5), hasTime: false, matchedText: ""))
        let observable = library.add(kind: .review, title: "@Observable replaces ObservableObject", body: "iOS 17+. Views track exactly the properties they read.", categoryIDs: [learning.id])

        let graphIdea = library.add(kind: .thought, title: "ThoughtCloud: graph view like Obsidian", categoryIDs: [projects.id, learning.id, work.id])
        library.add(kind: .thought, title: "Band name: Quiet Static", categoryIDs: [projects.id])
        library.add(kind: .thought, title: "Look into e-bikes")
        library.add(kind: .thought, title: "The Overstory, rec from Jordan")

        func timed(_ day: Date) -> DetectedDate { DetectedDate(date: day, hasTime: true, matchedText: "") }
        let offsite = library.add(kind: .event, title: "Team offsite", categoryIDs: [work.id], date: timed(days(0, hour: 15)))
        library.setEventTimes(offsite.id, start: days(0, hour: 15), end: days(0, hour: 16).addingTimeInterval(1800), isAllDay: false)
        let dinner = library.add(kind: .event, title: "Sam's birthday dinner", body: "Where: Lupa, 170 Thompson St\n- Bring the card", categoryIDs: [home.id], date: timed(days(2, hour: 19)))
        library.add(kind: .event, title: "Dentist", body: "Where: Dr. Okafor, 2nd floor", categoryIDs: [health.id], date: timed(days(4, hour: 10)))
        let lisbon = library.add(kind: .event, title: "Flight to Lisbon", body: "TP 214 · JFK 07:40", categoryIDs: [travel.id], date: timed(days(14, hour: 8)))
        library.add(kind: .event, title: "Quarterly review", categoryIDs: [work.id], date: timed(days(19, hour: 14)))
        let visit = library.add(kind: .event, title: "Mom visits", categoryIDs: [home.id], date: DetectedDate(date: days(36), hasTime: false, matchedText: ""))
        library.setEventTimes(visit.id, start: days(36), end: days(39), isAllDay: true)
        library.link(dinner.id, bday.id)
        library.link(lisbon.id, trip.id)

        library.link(flights.id, trip.id)
        library.link(gift.id, bday.id)
        library.link(dentist.id, appt.id)
        library.link(dashboard.id, oncall.id)
        library.link(standup.id, slides.id)
        library.link(graphIdea.id, observable.id)
        library.link(sleep.id, graphIdea.id)
        library.link(deck.id, slides.id)
        library.grade(observable.id, .gotIt)
    }
}
#endif
