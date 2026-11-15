import Foundation

public typealias GraphPoint = SIMD2<Double>

public enum GraphNodeID: Hashable, Sendable {
    case category(UUID)
    case inbox
    case item(UUID)

    public var itemID: UUID? {
        if case .item(let id) = self { return id }
        return nil
    }

    public var categoryID: UUID? {
        if case .category(let id) = self { return id }
        return nil
    }
}

public struct GraphNode: Identifiable, Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case hub(emoji: String, colorHex: String)
        case item(kind: ItemKind, style: CategoryStyle)
    }

    public var id: GraphNodeID
    public var label: String
    public var role: Role
    public var isDue = false
    public var isOverdue = false
    public var isFaded = false

    public init(id: GraphNodeID, label: String, role: Role, isDue: Bool = false, isOverdue: Bool = false, isFaded: Bool = false) {
        self.id = id
        self.label = label
        self.role = role
        self.isDue = isDue
        self.isOverdue = isOverdue
        self.isFaded = isFaded
    }

    public var isHub: Bool {
        if case .hub = role { return true }
        return false
    }

    static func hub(_ id: GraphNodeID) -> GraphNode {
        GraphNode(id: id, label: "hub", role: .hub(emoji: "•", colorHex: CategoryPalette.inboxHex))
    }

    static func leaf(_ id: GraphNodeID) -> GraphNode {
        GraphNode(id: id, label: "leaf", role: .item(kind: .thought, style: .inbox))
    }
}

public struct GraphEdge: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Item belongs to a category (or the Inbox).
        case membership
        /// Item-to-item connection (promoted or manual).
        case link
    }

    public var a: GraphNodeID
    public var b: GraphNodeID
    public var kind: Kind

    public init(a: GraphNodeID, b: GraphNodeID, kind: Kind) {
        self.a = a
        self.b = b
        self.kind = kind
    }

    public func touches(_ id: GraphNodeID) -> Bool { a == id || b == id }

    public func other(than id: GraphNodeID) -> GraphNodeID? {
        if a == id { return b }
        if b == id { return a }
        return nil
    }
}

public struct CloudGraph: Hashable, Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    public init(nodes: [GraphNode], edges: [GraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }

    public static let empty = CloudGraph(nodes: [], edges: [])

    public func node(_ id: GraphNodeID) -> GraphNode? { nodes.first { $0.id == id } }

    public func neighbors(of id: GraphNodeID) -> [GraphNodeID] {
        edges.compactMap { $0.other(than: id) }
    }
}

public struct GraphOptions: Hashable, Sendable {
    public var showCompleted: Bool
    public var kinds: Set<ItemKind>

    public init(showCompleted: Bool = true, kinds: Set<ItemKind> = Set(ItemKind.allCases)) {
        self.showCompleted = showCompleted
        self.kinds = kinds
    }
}

public enum GraphBuilder {
    @MainActor
    public static func build(from library: Library, options: GraphOptions = GraphOptions()) -> CloudGraph {
        let now = library.now
        let sectioner = TodoSectioner(calendar: library.calendar)
        let visible = library.items.filter { item in
            !item.isArchived && options.kinds.contains(item.kind) && (options.showCompleted || !item.isCompleted)
        }
        let visibleIDs = Set(visible.map(\.id))

        var nodes: [GraphNode] = library.categories.map {
            GraphNode(id: .category($0.id), label: $0.name, role: .hub(emoji: $0.emoji, colorHex: $0.colorHex))
        }
        var edges: [GraphEdge] = []
        var needsInbox = false

        for item in visible {
            let style = library.style(for: item)
            let id = GraphNodeID.item(item.id)
            nodes.append(GraphNode(
                id: id,
                label: item.displayTitle,
                role: .item(kind: item.kind, style: style),
                isDue: item.isReviewable && library.isDue(item, now: now),
                isOverdue: sectioner.isOverdue(item, now: now),
                isFaded: item.isCompleted
            ))
            let categories = style.categories
            if categories.isEmpty {
                needsInbox = true
                edges.append(GraphEdge(a: .inbox, b: id, kind: .membership))
            } else {
                edges += categories.map { GraphEdge(a: .category($0.id), b: id, kind: .membership) }
            }
        }

        if needsInbox {
            nodes.insert(GraphNode(id: .inbox, label: "Inbox", role: .hub(emoji: "📥", colorHex: CategoryPalette.inboxHex)), at: 0)
        }

        for link in library.links where visibleIDs.contains(link.from) && visibleIDs.contains(link.to) {
            edges.append(GraphEdge(a: .item(link.from), b: .item(link.to), kind: .link))
        }

        return CloudGraph(nodes: nodes, edges: edges)
    }
}
