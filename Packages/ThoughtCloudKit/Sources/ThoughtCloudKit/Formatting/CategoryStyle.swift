import Foundation

/// How an item's categories are painted:
/// none → Inbox grey, one → solid, two → split, three or more → white ("many").
public enum CategoryStyle: Hashable, Sendable {
    case inbox
    case single(ItemCategory)
    case pair(ItemCategory, ItemCategory)
    case many([ItemCategory])

    public static func resolve(_ ids: [UUID], in categories: [ItemCategory]) -> CategoryStyle {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        let resolved = ids.compactMap { id -> ItemCategory? in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
        switch resolved.count {
        case 0: return .inbox
        case 1: return .single(resolved[0])
        case 2: return .pair(resolved[0], resolved[1])
        default: return .many(resolved)
        }
    }

    public var categories: [ItemCategory] {
        switch self {
        case .inbox: []
        case .single(let c): [c]
        case .pair(let a, let b): [a, b]
        case .many(let all): all
        }
    }

    /// Colours to paint, in order. Pair → two halves. Many → white only.
    public var colorHexes: [String] {
        switch self {
        case .inbox: [CategoryPalette.inboxHex]
        case .single(let c): [c.colorHex]
        case .pair(let a, let b): [a.colorHex, b.colorHex]
        case .many: [CategoryPalette.manyHex]
        }
    }

    /// Colours for the thin "which ones" ring, shown when zoomed in.
    public var ringHexes: [String] {
        if case .many(let all) = self { return all.map(\.colorHex) }
        return []
    }

    public var primaryHex: String { colorHexes[0] }

    public var emojis: String {
        if case .inbox = self { return "📥" }
        return categories.map(\.emoji).joined()
    }

    public var label: String {
        if case .inbox = self { return "Inbox" }
        return categories.map(\.name).joined(separator: " · ")
    }
}
