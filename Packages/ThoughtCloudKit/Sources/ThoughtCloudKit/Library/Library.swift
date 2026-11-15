import Foundation
import Observation

public enum ReviewGrade: Sendable {
    case gotIt, again
}

/// The single source of truth the UI talks to. Every command mutates the
/// snapshot and persists it immediately. All rules (scheduling, colours,
/// parsing) live in small value types; this class only orchestrates.
@MainActor
@Observable
public final class Library {
    public private(set) var snapshot: LibrarySnapshot
    /// Last persistence problem, for the UI to show. Data stays in memory.
    public var lastError: String?

    public let scheduler: ReviewScheduler
    public let eventScheduler: EventReviewScheduler
    public let calendar: Calendar
    @ObservationIgnored private let persistence: any LibraryPersisting
    @ObservationIgnored private let dates: any DateProviding
    @ObservationIgnored private let calendarSync: (any CalendarSyncing)?

    public init(
        persistence: any LibraryPersisting,
        dates: any DateProviding = SystemDateProvider(),
        calendar: Calendar = .current,
        calendarSync: (any CalendarSyncing)? = nil
    ) {
        self.persistence = persistence
        self.dates = dates
        self.calendar = calendar
        self.calendarSync = calendarSync
        self.scheduler = ReviewScheduler(calendar: calendar)
        self.eventScheduler = EventReviewScheduler(calendar: calendar)
        do {
            snapshot = try persistence.load()
        } catch {
            snapshot = .empty
            lastError = error.localizedDescription
        }
        archiveExpiredReviews(save: false)
    }

    public var now: Date { dates.now() }

    // MARK: - Queries

    public var items: [Item] { snapshot.items }
    public var categories: [ItemCategory] { snapshot.categories }
    public var links: [ItemLink] { snapshot.links }

    public func item(_ id: UUID) -> Item? { snapshot.items.first { $0.id == id } }
    public func category(_ id: UUID) -> ItemCategory? { snapshot.categories.first { $0.id == id } }

    public func activeItems(of kind: ItemKind) -> [Item] {
        snapshot.items.filter { $0.kind == kind && !$0.isArchived }
    }

    public func items(inCategory id: UUID) -> [Item] {
        snapshot.items.filter { $0.categoryIDs.contains(id) && !$0.isArchived }
    }

    public func style(for item: Item) -> CategoryStyle {
        CategoryStyle.resolve(item.categoryIDs, in: snapshot.categories)
    }

    public func linkedItems(of id: UUID) -> [Item] {
        let ids = snapshot.links.compactMap { $0.other(than: id) }
        return ids.compactMap(item)
    }

    /// Review cards and events that are due, oldest first.
    public func dueReviews(inCategory categoryID: UUID? = nil) -> [Item] {
        let now = now
        return snapshot.items
            .filter { item in
                guard item.isReviewable, !item.isArchived else { return false }
                if let categoryID, !item.categoryIDs.contains(categoryID) { return false }
                return isDue(item, now: now)
            }
            .sorted { ($0.review!.nextReviewAt, $0.createdAt) < ($1.review!.nextReviewAt, $1.createdAt) }
    }

    /// Every active review card and event, for browsing.
    public func reviewableItems(inCategory categoryID: UUID? = nil) -> [Item] {
        snapshot.items
            .filter { $0.isReviewable && !$0.isArchived && (categoryID == nil || $0.categoryIDs.contains(categoryID!)) }
            .sorted { ($0.review?.nextReviewAt ?? .distantFuture) < ($1.review?.nextReviewAt ?? .distantFuture) }
    }

    /// Active events, soonest first.
    public func upcomingEvents() -> [Item] {
        activeItems(of: .event).filter { $0.event != nil }.sorted { $0.event!.start < $1.event!.start }
    }

    public func isDue(_ item: Item, now: Date) -> Bool {
        guard let state = item.review else { return false }
        if item.kind == .event, let event = item.event {
            return eventScheduler.isDue(state, event: event, now: now)
        }
        return scheduler.isDue(state, now: now)
    }

    /// True when "got it" would retire the item (an event on its day).
    public func retiresAfterGotIt(_ id: UUID) -> Bool {
        guard let item = item(id), item.kind == .event, let event = item.event, let state = item.review else { return false }
        let now = now
        let next = eventScheduler.gotIt(state, event: event, now: now).nextReviewAt
        return eventScheduler.isExpired(event, now: next)
    }

    /// Days until the item comes back after a swipe, for the Review buttons.
    public func nextReviewGapDays(for id: UUID, _ grade: ReviewGrade) -> Int? {
        guard let item = item(id), let state = item.review else { return nil }
        let now = now
        if item.kind == .event, let event = item.event {
            return grade == .gotIt
                ? eventScheduler.daysUntilNextReview(afterGotIt: state, event: event, now: now)
                : eventScheduler.daysUntilNextReview(afterAgain: state, now: now)
        }
        return grade == .gotIt
            ? scheduler.daysUntilNextReview(afterGotIt: state, now: now)
            : scheduler.daysUntilNextReview(afterAgain: state, now: now)
    }

    // MARK: - Items

    @discardableResult
    public func add(kind: ItemKind, title: String, body: String = "", categoryIDs: [UUID] = [], date: DetectedDate? = nil, event: EventInfo? = nil, addToCalendar: Bool = true) -> Item {
        let now = now
        var item = Item(kind: kind, title: title, body: body, categoryIDs: categoryIDs, createdAt: now)
        switch kind {
        case .todo:
            item.dueDate = date?.date
            item.dueHasTime = date?.hasTime ?? false
        case .review:
            item.review = scheduler.initialState(now: now, rememberUntil: date?.date)
        case .event:
            var event = event ?? EventInfo.make(from: date, now: now, calendar: calendar)
            event.addToCalendar = addToCalendar
            item.event = event
            item.review = eventScheduler.initialState(for: event, now: now)
        case .thought:
            break
        }
        snapshot.items.append(item)
        syncCalendar(item.id)
        commit()
        return self.item(item.id) ?? item
    }

    public func updateText(_ id: UUID, title: String, body: String) {
        mutate(id, syncingCalendar: true) { item in
            item.title = title
            item.body = body
        }
    }

    public func setKind(_ id: UUID, _ kind: ItemKind) {
        let now = now
        mutate(id, syncingCalendar: true) { item in
            item.changeKind(to: kind, now: now)
            if kind == .event {
                let date = item.dueDate.map { DetectedDate(date: $0, hasTime: item.dueHasTime, matchedText: "") }
                    ?? item.review?.rememberUntil.map { DetectedDate(date: $0, hasTime: false, matchedText: "") }
                let event = item.event ?? EventInfo.make(from: date, now: now, calendar: calendar)
                item.event = event
                item.review = eventScheduler.initialState(for: event, now: now)
            }
        }
    }

    public func setEventTimes(_ id: UUID, start: Date, end: Date, isAllDay: Bool) {
        let now = now
        mutate(id, syncingCalendar: true) { item in
            guard var event = item.event else { return }
            event.isAllDay = isAllDay
            event.start = isAllDay ? calendar.startOfDay(for: start) : start
            event.end = max(isAllDay ? calendar.startOfDay(for: end) : end, event.start)
            item.event = event
            item.review = eventScheduler.initialState(for: event, now: now)
            item.archivedAt = nil
        }
    }

    public func setAddToCalendar(_ id: UUID, _ on: Bool) {
        mutate(id, syncingCalendar: true) { $0.event?.addToCalendar = on }
    }

    /// Writes events that should be in the calendar but aren't yet
    /// (e.g. created before calendar access was granted).
    public func syncPendingCalendarEvents() {
        let pending = snapshot.items.filter { item in
            guard item.kind == .event, !item.isArchived, let event = item.event else { return false }
            return event.addToCalendar && event.calendarEventID == nil
        }
        guard !pending.isEmpty else { return }
        for item in pending { syncCalendar(item.id) }
        commit()
    }

    public func setCategories(_ id: UUID, _ categoryIDs: [UUID]) {
        mutate(id) { $0.categoryIDs = categoryIDs }
    }

    public func setDueDate(_ id: UUID, _ date: Date?, hasTime: Bool) {
        mutate(id) { item in
            item.dueDate = date
            item.dueHasTime = date != nil && hasTime
        }
    }

    public func setRememberUntil(_ id: UUID, _ date: Date?) {
        let now = now
        mutate(id) { item in
            if item.review == nil { item.review = scheduler.initialState(now: now, rememberUntil: nil) }
            item.review?.rememberUntil = date
            if date != nil { item.archivedAt = nil }
        }
    }

    public func toggleCompleted(_ id: UUID) {
        let now = now
        mutate(id) { item in
            item.completedAt = item.completedAt == nil ? now : nil
        }
    }

    public func grade(_ id: UUID, _ grade: ReviewGrade) {
        let now = now
        mutate(id) { item in
            if item.kind == .event, let event = item.event {
                let state = item.review ?? eventScheduler.initialState(for: event, now: now)
                item.review = grade == .gotIt ? eventScheduler.gotIt(state, event: event, now: now) : eventScheduler.again(state, now: now)
                return
            }
            let state = item.review ?? scheduler.initialState(now: now, rememberUntil: nil)
            item.review = grade == .gotIt ? scheduler.gotIt(state, now: now) : scheduler.again(state, now: now)
        }
    }

    /// Restores a previous review state exactly (used by undo).
    public func setReviewState(_ id: UUID, _ state: ReviewState?) {
        mutate(id) { $0.review = state }
    }

    public func setArchived(_ id: UUID, _ archived: Bool) {
        let now = now
        mutate(id) { $0.archivedAt = archived ? now : nil }
    }

    public func delete(_ id: UUID) {
        if let calendarID = item(id)?.event?.calendarEventID {
            perform { try calendarSync?.remove(id: calendarID) }
        }
        snapshot.items.removeAll { $0.id == id }
        snapshot.links.removeAll { $0.from == id || $0.to == id }
        commit()
    }

    /// Turns a thought into a todo or review card. The original stays and the
    /// two are linked, which is what makes the Cloud interconnected.
    @discardableResult
    public func promote(_ id: UUID, to kind: ItemKind) -> Item? {
        guard let source = item(id), kind != source.kind else { return nil }
        let now = now
        var copy = Item(kind: kind, title: source.title, body: source.body, categoryIDs: source.categoryIDs, createdAt: now)
        if kind == .review { copy.review = scheduler.initialState(now: now, rememberUntil: nil) }
        if kind == .event {
            let event = EventInfo.make(from: nil, now: now, calendar: calendar)
            copy.event = event
            copy.review = eventScheduler.initialState(for: event, now: now)
        }
        snapshot.items.append(copy)
        snapshot.links.append(ItemLink(from: source.id, to: copy.id, kind: .promoted, createdAt: now))
        syncCalendar(copy.id)
        commit()
        return item(copy.id) ?? copy
    }

    public func link(_ a: UUID, _ b: UUID) {
        guard a != b, item(a) != nil, item(b) != nil, !snapshot.links.contains(where: { $0.connects(a, b) }) else { return }
        snapshot.links.append(ItemLink(from: a, to: b, kind: .manual, createdAt: now))
        commit()
    }

    public func unlink(_ a: UUID, _ b: UUID) {
        snapshot.links.removeAll { $0.connects(a, b) }
        commit()
    }

    /// Re-evaluates time-based state (e.g. retiring expired review cards).
    public func refresh() {
        archiveExpiredReviews(save: true)
    }

    // MARK: - Categories

    @discardableResult
    public func createCategory(name: String, emoji: String? = nil, colorHex: String? = nil) -> ItemCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = CategoryMatcher.find(trimmed, in: snapshot.categories) { return existing }
        let category = ItemCategory(
            name: trimmed,
            emoji: emoji ?? CategoryPalette.defaultEmoji,
            colorHex: colorHex ?? CategoryPalette.nextColor(excluding: snapshot.categories.map(\.colorHex)),
            createdAt: now
        )
        snapshot.categories.append(category)
        commit()
        return category
    }

    public func categoryIDs(forHashtags tags: [String]) -> [UUID] {
        var ids: [UUID] = []
        for tag in tags {
            let category = CategoryMatcher.find(tag, in: snapshot.categories)
                ?? createCategory(name: CategoryMatcher.displayName(fromHashtag: tag))
            if !ids.contains(category.id) { ids.append(category.id) }
        }
        return ids
    }

    public func updateCategory(_ category: ItemCategory) {
        guard let index = snapshot.categories.firstIndex(where: { $0.id == category.id }) else { return }
        snapshot.categories[index] = category
        commit()
    }

    public func deleteCategory(_ id: UUID) {
        snapshot.categories.removeAll { $0.id == id }
        for index in snapshot.items.indices {
            snapshot.items[index].categoryIDs.removeAll { $0 == id }
        }
        commit()
    }

    public static let defaultCategories: [(String, String)] = [
        ("Work", "💼"), ("Home", "🏠"), ("Health", "💪"), ("Learning", "📚"), ("Travel", "✈️"),
    ]

    public func seedDefaultCategoriesIfNeeded() {
        guard snapshot.categories.isEmpty, snapshot.items.isEmpty else { return }
        for (name, emoji) in Self.defaultCategories {
            createCategory(name: name, emoji: emoji)
        }
    }

    // MARK: - Export

    public func exportData() -> Data {
        (try? JSONEncoder.library.encode(snapshot)) ?? Data()
    }

    // MARK: - Internals

    private func mutate(_ id: UUID, syncingCalendar: Bool = false, _ change: (inout Item) -> Void) {
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
        change(&snapshot.items[index])
        snapshot.items[index].updatedAt = now
        if syncingCalendar { syncCalendar(id) }
        commit()
    }

    /// Makes the calendar match the item: creates/updates it when it's an event
    /// that wants to be in the calendar, removes it otherwise.
    private func syncCalendar(_ id: UUID) {
        guard let calendarSync, let index = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
        let item = snapshot.items[index]
        let existingID = item.event?.calendarEventID
        if item.kind == .event, let event = item.event, event.addToCalendar {
            perform {
                let newID = try calendarSync.save(CalendarEventDraft(item: item, event: event), existingID: existingID)
                snapshot.items[index].event?.calendarEventID = newID
            }
        } else if let existingID {
            perform {
                try calendarSync.remove(id: existingID)
                snapshot.items[index].event?.calendarEventID = nil
            }
        }
    }

    /// Runs a calendar call. Missing permission is quiet (retried later); anything else is surfaced.
    private func perform(_ body: () throws -> Void) {
        do {
            try body()
        } catch CalendarSyncError.notAuthorized {
            return
        } catch {
            lastError = "Calendar: \(error.localizedDescription)"
        }
    }

    private func archiveExpiredReviews(save: Bool) {
        let now = now
        var changed = false
        for index in snapshot.items.indices {
            let item = snapshot.items[index]
            guard !item.isArchived else { continue }
            let expired: Bool
            switch item.kind {
            case .review: expired = item.review.map { scheduler.isExpired($0, now: now) } ?? false
            case .event: expired = item.event.map { eventScheduler.isExpired($0, now: now) } ?? false
            case .todo, .thought: expired = false
            }
            guard expired else { continue }
            snapshot.items[index].archivedAt = now
            changed = true
        }
        if changed && save { commit() }
    }

    private func commit() {
        do {
            try persistence.save(snapshot)
            if lastError?.hasPrefix("Couldn't save") == true { lastError = nil }
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
