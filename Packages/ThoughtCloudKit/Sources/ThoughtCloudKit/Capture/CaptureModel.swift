import Foundation
import Observation

/// State behind the capture sheet. Parses on every keystroke so the UI can
/// show what will be saved; nothing here ever blocks saving.
@MainActor
@Observable
public final class CaptureModel {
    public var text: String = "" {
        didSet { draft = parser.parse(text) }
    }
    public private(set) var draft: CaptureDraft
    public private(set) var kindWasChosen = false
    public private(set) var dateDismissed = false
    /// Events only: whether this one goes into the iPhone Calendar.
    public var addToCalendar = true

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let parser: CaptureParser
    @ObservationIgnored private let presetCategoryIDs: [UUID]
    @ObservationIgnored private let presetKind: ItemKind?
    private var chosenKind: ItemKind?
    /// Event times picked by hand; they win over any date in the text.
    private var manualEvent: EventInfo?
    private var manualCategoryIDs: [UUID]

    public init(library: Library, parser: CaptureParser, presetCategoryIDs: [UUID] = [], presetKind: ItemKind? = nil) {
        self.library = library
        self.parser = parser
        self.presetCategoryIDs = presetCategoryIDs
        self.presetKind = presetKind
        self.manualCategoryIDs = presetCategoryIDs
        self.draft = parser.parse("")
        reset()
    }

    // MARK: - Derived

    public var kind: ItemKind { chosenKind ?? draft.suggestedKind }

    public var canSave: Bool { !draft.isEmpty }

    /// For events: the start/end that will be saved.
    public var eventPreview: EventInfo? {
        guard kind == .event else { return nil }
        if let manualEvent { return manualEvent }
        return EventInfo.make(from: detectedDate, now: library.now, calendar: library.calendar)
    }

    public var detectedDate: DetectedDate? {
        dateDismissed || kind == .thought ? nil : draft.detectedDate
    }

    /// Manually toggled categories first (in tap order), then ones from `#tags`.
    public var selectedCategoryIDs: [UUID] {
        var ids = manualCategoryIDs
        for tag in draft.hashtags {
            if let category = CategoryMatcher.find(tag, in: library.categories), !ids.contains(category.id) {
                ids.append(category.id)
            }
        }
        return ids
    }

    /// `#tags` that don't match a category yet; they'll be created on save.
    public var newCategoryNames: [String] {
        draft.hashtags
            .filter { CategoryMatcher.find($0, in: library.categories) == nil }
            .map(CategoryMatcher.displayName(fromHashtag:))
    }

    /// Most recently used first, so the likely chip is under your thumb.
    public var orderedCategories: [ItemCategory] {
        var lastUsed: [UUID: Date] = [:]
        for item in library.items {
            for id in item.categoryIDs where (lastUsed[id] ?? .distantPast) < item.createdAt {
                lastUsed[id] = item.createdAt
            }
        }
        return library.categories.enumerated().sorted { lhs, rhs in
            let l = lastUsed[lhs.element.id] ?? .distantPast
            let r = lastUsed[rhs.element.id] ?? .distantPast
            return l != r ? l > r : lhs.offset < rhs.offset
        }.map(\.element)
    }

    public var autocomplete: [ItemCategory] {
        guard let typed = draft.hashtagInProgress else { return [] }
        let key = CategoryMatcher.key(typed)
        return orderedCategories.filter { key.isEmpty || CategoryMatcher.key($0.name).hasPrefix(key) }
    }

    // MARK: - Intents

    public func chooseKind(_ kind: ItemKind) {
        chosenKind = kind
        kindWasChosen = true
    }

    public func dismissDate() {
        dateDismissed = true
        manualEvent = nil
    }

    public func setEventTimes(start: Date, end: Date, isAllDay: Bool) {
        let calendar = library.calendar
        let start = isAllDay ? calendar.startOfDay(for: start) : start
        let end = isAllDay ? calendar.startOfDay(for: end) : end
        manualEvent = EventInfo(start: start, end: end, isAllDay: isAllDay)
    }

    public func toggleCategory(_ id: UUID) {
        if let index = manualCategoryIDs.firstIndex(of: id) {
            manualCategoryIDs.remove(at: index)
        } else if let category = library.category(id), draft.hashtags.contains(where: { CategoryMatcher.key($0) == CategoryMatcher.key(category.name) }) {
            removeHashtags(matching: category)
        } else {
            manualCategoryIDs.append(id)
        }
    }

    public func complete(with category: ItemCategory) {
        guard let typed = draft.hashtagInProgress else { return }
        text = String(text.dropLast(typed.count + 1)) + "#" + Self.slug(for: category.name) + " "
    }

    @discardableResult
    public func save() -> Item? {
        guard canSave else { return nil }
        var ids = manualCategoryIDs
        for id in library.categoryIDs(forHashtags: draft.hashtags) where !ids.contains(id) {
            ids.append(id)
        }
        let item = library.add(kind: kind, title: draft.title, body: draft.body, categoryIDs: ids, date: detectedDate, event: eventPreview, addToCalendar: addToCalendar)
        reset()
        return item
    }

    public func reset() {
        text = ""
        chosenKind = presetKind
        kindWasChosen = presetKind != nil
        dateDismissed = false
        manualEvent = nil
        addToCalendar = true
        manualCategoryIDs = presetCategoryIDs
    }

    // MARK: - Helpers

    static func slug(for name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    private func removeHashtags(matching category: ItemCategory) {
        let key = CategoryMatcher.key(category.name)
        let pattern = try! NSRegularExpression(pattern: #"(?<![\w#])#([A-Za-z][\w-]*)\s?"#)
        let ns = text as NSString
        var result = text
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        where CategoryMatcher.key(ns.substring(with: match.range(at: 1))) == key {
            result = (result as NSString).replacingCharacters(in: match.range, with: "")
        }
        text = result
    }
}
