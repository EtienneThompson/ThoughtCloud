import Foundation

/// Pan/zoom state for the Cloud. Pure maths so gestures are testable.
public struct GraphCamera: Hashable, Sendable {
    public static let minZoom = 0.25
    public static let maxZoom = 4.0
    /// Item names start appearing at this zoom and are fully visible at `labelFadeEnd`.
    public static let labelFadeStart = 1.15
    public static let labelFadeEnd = 1.6

    public var center: GraphPoint
    public var zoom: Double

    public init(center: GraphPoint = .zero, zoom: Double = 1) {
        self.center = center
        self.zoom = Self.clamp(zoom)
    }

    public func toScreen(_ world: GraphPoint, viewSize: GraphPoint) -> GraphPoint {
        (world - center) * zoom + viewSize / 2
    }

    public func toWorld(_ screen: GraphPoint, viewSize: GraphPoint) -> GraphPoint {
        (screen - viewSize / 2) / zoom + center
    }

    /// Zooms while keeping the world point under `anchor` fixed on screen.
    public mutating func zoom(by factor: Double, anchor: GraphPoint, viewSize: GraphPoint) {
        let world = toWorld(anchor, viewSize: viewSize)
        zoom = Self.clamp(zoom * factor)
        center = world - (anchor - viewSize / 2) / zoom
    }

    public mutating func pan(byScreen delta: GraphPoint) {
        center -= delta / zoom
    }

    public static func fitting(min lo: GraphPoint, max hi: GraphPoint, viewSize: GraphPoint, padding: Double) -> GraphCamera {
        let size = pointwiseMax(hi - lo, GraphPoint(1, 1))
        let available = pointwiseMax(viewSize - GraphPoint(padding, padding) * 2, GraphPoint(1, 1))
        let z = Swift.min(available.x / size.x, available.y / size.y)
        return GraphCamera(center: (lo + hi) / 2, zoom: z)
    }

    public var labelOpacity: Double {
        Swift.min(1, Swift.max(0, (zoom - Self.labelFadeStart) / (Self.labelFadeEnd - Self.labelFadeStart)))
    }

    private static func clamp(_ z: Double) -> Double {
        Swift.min(maxZoom, Swift.max(minZoom, z))
    }
}
