import Foundation

/// Everything the app stores, as one value. Persisted as a single JSON document.
public struct LibrarySnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var items: [Item]
    public var categories: [ItemCategory]
    public var links: [ItemLink]

    public init(items: [Item] = [], categories: [ItemCategory] = [], links: [ItemLink] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.items = items
        self.categories = categories
        self.links = links
    }

    public static let empty = LibrarySnapshot()
}

public extension JSONEncoder {
    static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
