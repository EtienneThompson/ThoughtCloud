import Foundation

/// A small deterministic force-directed layout (repulsion + springs + gravity),
/// in the spirit of d3-force. Pure value type: the view drives `step()`.
public struct ForceLayout: Sendable {
    public struct Parameters: Sendable {
        public var hubRepulsion = 2600.0
        public var itemRepulsion = 520.0
        public var repulsionCutoff = 300.0
        public var membershipLength = 48.0
        public var membershipStrength = 0.08
        public var linkLength = 70.0
        public var linkStrength = 0.03
        public var gravity = 0.004
        public var damping = 0.55
        public var alphaDecay = 0.985
        public var minAlpha = 0.02
        public var settledSpeed = 0.1
        public init() {}
    }

    public var parameters: Parameters
    public private(set) var alpha: Double = 1

    private var order: [GraphNodeID] = []
    private var index: [GraphNodeID: Int] = [:]
    private var pos: [GraphPoint] = []
    private var vel: [GraphPoint] = []
    private var isHub: [Bool] = []
    private var pinned: [Int: GraphPoint] = [:]
    private var springs: [(Int, Int, Double, Double)] = []
    private var rng: SplitMix64
    private var maxSpeed = Double.infinity

    public init(seed: UInt64 = 42, parameters: Parameters = Parameters()) {
        self.rng = SplitMix64(seed: seed)
        self.parameters = parameters
    }

    // MARK: - Reading

    public var positions: [GraphNodeID: GraphPoint] {
        Dictionary(uniqueKeysWithValues: zip(order, pos))
    }

    public func position(of id: GraphNodeID) -> GraphPoint? {
        index[id].map { pos[$0] }
    }

    public var isSettled: Bool {
        alpha <= parameters.minAlpha && maxSpeed < parameters.settledSpeed
    }

    public var bounds: (min: GraphPoint, max: GraphPoint)? {
        guard var lo = pos.first else { return nil }
        var hi = lo
        for p in pos {
            lo = pointwiseMin(lo, p)
            hi = pointwiseMax(hi, p)
        }
        return (lo, hi)
    }

    // MARK: - Updating the node set

    /// Adopts the graph's nodes and edges. Existing nodes keep their positions;
    /// new nodes appear next to a neighbour so the picture doesn't jump.
    public mutating func sync(with graph: CloudGraph) {
        let wasEmpty = order.isEmpty
        let oldPositions = positions
        let oldVelocities = Dictionary(uniqueKeysWithValues: zip(order, vel))
        let oldPins = Dictionary(uniqueKeysWithValues: pinned.map { (order[$0.key], $0.value) })

        order = graph.nodes.map(\.id)
        index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        isHub = graph.nodes.map(\.isHub)
        pos = Array(repeating: .zero, count: order.count)
        vel = order.map { oldVelocities[$0] ?? .zero }
        pinned = [:]
        for (id, point) in oldPins { if let i = index[id] { pinned[i] = point } }

        let hubCount = max(1, isHub.filter { $0 }.count)
        var hubOrdinal = 0
        var placed = Set<Int>()
        for (i, id) in order.enumerated() {
            if let old = oldPositions[id] {
                pos[i] = old
                placed.insert(i)
            } else if isHub[i] && wasEmpty {
                let angle = Double(hubOrdinal) / Double(hubCount) * 2 * .pi
                pos[i] = GraphPoint(cos(angle), sin(angle)) * 150
                hubOrdinal += 1
                placed.insert(i)
            }
        }

        springs = graph.edges.compactMap { edge in
            guard let a = index[edge.a], let b = index[edge.b] else { return nil }
            return edge.kind == .membership
                ? (a, b, parameters.membershipLength, parameters.membershipStrength)
                : (a, b, parameters.linkLength, parameters.linkStrength)
        }

        // Place the rest beside an already-placed neighbour (repeat to handle chains).
        var added = false
        for _ in 0..<3 {
            for i in order.indices where !placed.contains(i) {
                let neighbour = springs.lazy.compactMap { s -> Int? in
                    if s.0 == i, placed.contains(s.1) { return s.1 }
                    if s.1 == i, placed.contains(s.0) { return s.0 }
                    return nil
                }.first
                guard let neighbour else { continue }
                pos[i] = pos[neighbour] + randomOffset(radius: 12...24)
                placed.insert(i)
                added = true
            }
        }
        for i in order.indices where !placed.contains(i) {
            pos[i] = randomOffset(radius: 0...160)
            added = true
        }

        if wasEmpty { alpha = 1 } else if added { reheat(to: 0.3) }
        maxSpeed = .infinity
    }

    // MARK: - Simulation

    public mutating func reheat(to value: Double = 0.3) {
        alpha = max(alpha, value)
        maxSpeed = .infinity
    }

    public mutating func pin(_ id: GraphNodeID, at point: GraphPoint) {
        guard let i = index[id] else { return }
        pinned[i] = point
        pos[i] = point
        vel[i] = .zero
    }

    public mutating func unpin(_ id: GraphNodeID) {
        guard let i = index[id] else { return }
        pinned[i] = nil
    }

    public mutating func step() {
        let p = parameters
        let n = pos.count
        let cutoff2 = p.repulsionCutoff * p.repulsionCutoff

        for i in 0..<n {
            for j in (i + 1)..<max(i + 1, n) {
                var d = pos[j] - pos[i]
                var dist2 = (d * d).sum()
                if dist2 > cutoff2 { continue }
                if dist2 < 1 {
                    d = randomOffset(radius: 0.5...1)
                    dist2 = 1
                }
                let strength = (isHub[i] || isHub[j] ? p.hubRepulsion : p.itemRepulsion) * alpha / dist2
                let force = d / dist2.squareRoot() * strength
                vel[i] -= force
                vel[j] += force
            }
        }

        for (a, b, length, k) in springs {
            let d = pos[b] - pos[a]
            let dist = max((d * d).sum().squareRoot(), 0.0001)
            let f = d * ((dist - length) / dist * k * alpha * 2)
            vel[a] += f
            vel[b] -= f
        }

        var fastest = 0.0
        for i in 0..<n {
            if let pin = pinned[i] {
                pos[i] = pin
                vel[i] = .zero
                continue
            }
            vel[i] -= pos[i] * (p.gravity * alpha)
            vel[i] *= p.damping
            pos[i] += vel[i]
            fastest = max(fastest, (vel[i] * vel[i]).sum().squareRoot())
        }
        maxSpeed = fastest
        alpha = max(alpha * p.alphaDecay, p.minAlpha)
    }

    public mutating func settle(maxSteps: Int) {
        for _ in 0..<maxSteps {
            step()
            if isSettled { return }
        }
    }

    // MARK: - Hit testing

    public func hitTest(_ screenPoint: GraphPoint, camera: GraphCamera, viewSize: GraphPoint, radius: Double) -> GraphNodeID? {
        var best: (GraphNodeID, Double)?
        for (i, id) in order.enumerated() {
            let s = camera.toScreen(pos[i], viewSize: viewSize) - screenPoint
            let dist = (s * s).sum().squareRoot()
            if dist <= radius, dist < (best?.1 ?? .infinity) { best = (id, dist) }
        }
        return best?.0
    }

    private mutating func randomOffset(radius: ClosedRange<Double>) -> GraphPoint {
        let angle = rng.nextDouble() * 2 * .pi
        let r = radius.lowerBound + rng.nextDouble() * (radius.upperBound - radius.lowerBound)
        return GraphPoint(cos(angle), sin(angle)) * r
    }
}

/// Tiny deterministic RNG so layouts are reproducible.
struct SplitMix64: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
