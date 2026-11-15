import Foundation

public struct ItemCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    /// `#RRGGBB`
    public var colorHex: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, emoji: String, colorHex: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

public enum CategoryPalette {
    /// Distinct, dark-mode friendly colours. Deliberately excludes white and grey,
    /// which mean "many categories" and "Inbox".
    public static let colors: [String] = [
        "#64D2FF", "#30D158", "#FF6482", "#BF5AF2", "#FF9F0A",
        "#FFD60A", "#5E5CE6", "#40C8E0", "#FF453A", "#AC8E68",
    ]
    public static let inboxHex = "#6E6E78"
    public static let manyHex = "#F4F4F7"
    public static let defaultEmoji = "🏷️"

    /// The first palette colour not already used, cycling when all are taken.
    public static func nextColor(excluding used: [String]) -> String {
        let usedSet = Set(used.map { $0.uppercased() })
        return colors.first { !usedSet.contains($0.uppercased()) } ?? colors[used.count % colors.count]
    }
}
