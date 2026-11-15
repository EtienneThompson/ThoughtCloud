import Foundation
import Observation

/// Interaction state for the Cloud screen: layout, camera, selection, gestures.
/// The SwiftUI view only draws this and forwards gestures to it.
@MainActor
@Observable
public final class CloudModel {
    public static let focusZoom = 1.7
    /// Fraction of the view height the selected node sits above centre (room for the sheet).
    public static let focusLift = 0.2
    static let tapSlop = 28.0
    static let hubSlop = 34.0

    public private(set) var graph: CloudGraph = .empty
    public private(set) var nodesByID: [GraphNodeID: GraphNode] = [:]
    public private(set) var layout: ForceLayout
    public var camera = GraphCamera(center: .zero, zoom: 0.8)
    public private(set) var viewSize = GraphPoint(390, 700)
    public private(set) var selection: GraphNodeID?
    public private(set) var draggingNode: GraphNodeID?
    /// Bumped on every simulation step so the view redraws.
    public private(set) var frame = 0

    /// Observed so the view's animation loop wakes as soon as a camera flight starts.
    private var cameraTarget: GraphCamera?
    @ObservationIgnored private var panStartCenter: GraphPoint?
    @ObservationIgnored private var hasFitted = false
    @ObservationIgnored private var dragStart: GraphPoint?

    public init(seed: UInt64 = 42) {
        layout = ForceLayout(seed: seed)
    }

    // MARK: - Data

    public func update(graph: CloudGraph) {
        self.graph = graph
        nodesByID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        layout.sync(with: graph)
        if let selection, nodesByID[selection] == nil { self.selection = nil }
        if !hasFitted && !graph.nodes.isEmpty {
            layout.settle(maxSteps: 300)
            fit(animated: false)
            hasFitted = true
        }
        frame += 1
    }

    public func setViewSize(_ size: GraphPoint) {
        let changed = size != viewSize
        viewSize = size
        if changed && hasFitted && selection == nil { fit(animated: false) }
    }

    // MARK: - Derived

    public var highlighted: Set<GraphNodeID> {
        guard let selection else { return [] }
        return Set(graph.neighbors(of: selection) + [selection])
    }

    public var selectedNode: GraphNode? { selection.flatMap { nodesByID[$0] } }

    public var needsAnimation: Bool {
        !layout.isSettled || draggingNode != nil || cameraTarget != nil
    }

    // MARK: - Animation

    /// Advances one frame. Call from a display-linked timeline.
    public func tick() {
        if !layout.isSettled || draggingNode != nil { layout.step() }
        if let target = cameraTarget {
            camera.center += (target.center - camera.center) * 0.18
            camera.zoom += (target.zoom - camera.zoom) * 0.18
            let delta = target.center - camera.center
            if (delta * delta).sum() < 0.01 && abs(target.zoom - camera.zoom) < 0.001 {
                camera = target
                cameraTarget = nil
            }
        }
        frame += 1
    }

    public func settleNow() {
        layout.settle(maxSteps: 5000)
        if let cameraTarget { camera = cameraTarget }
        cameraTarget = nil
    }

    // MARK: - Gestures

    public func tap(at point: GraphPoint) {
        if let id = hitTest(point) { select(id) } else { select(nil) }
    }

    public func select(_ id: GraphNodeID?) {
        selection = id
        guard let id, let position = layout.position(of: id) else { return }
        let zoom = max(camera.zoom, Self.focusZoom)
        let lift = viewSize.y * Self.focusLift / zoom
        cameraTarget = GraphCamera(center: position + GraphPoint(0, lift), zoom: zoom)
    }

    /// Continuous drag. `start` is where the finger went down.
    public func dragChanged(start: GraphPoint, location: GraphPoint) {
        if dragStart == nil {
            dragStart = start
            cameraTarget = nil
            if let id = hitTest(start) {
                draggingNode = id
                layout.reheat(to: 0.3)
            } else {
                panStartCenter = camera.center
            }
        }
        if let node = draggingNode {
            layout.pin(node, at: camera.toWorld(location, viewSize: viewSize))
        } else if let panStartCenter {
            camera.center = panStartCenter - (location - start) / camera.zoom
        }
        frame += 1
    }

    public func dragEnded() {
        if let node = draggingNode {
            layout.unpin(node)
            layout.reheat(to: 0.2)
        }
        draggingNode = nil
        panStartCenter = nil
        dragStart = nil
    }

    /// Incremental pinch: `factor` relative to the previous call.
    public func pinch(by factor: Double, anchor: GraphPoint) {
        cameraTarget = nil
        camera.zoom(by: factor, anchor: anchor, viewSize: viewSize)
        frame += 1
    }

    /// Zoom buttons: applied immediately around the view centre, no animation.
    public func zoom(by factor: Double) {
        cameraTarget = nil
        camera.zoom(by: factor, anchor: viewSize / 2, viewSize: viewSize)
        frame += 1
    }

    public func fit(animated: Bool = true) {
        guard let bounds = layout.bounds else { return }
        let target = GraphCamera.fitting(min: bounds.min, max: bounds.max, viewSize: viewSize, padding: 48)
        let capped = GraphCamera(center: target.center, zoom: min(target.zoom, 1.4))
        if animated { cameraTarget = capped } else { cameraTarget = nil; camera = capped; frame += 1 }
    }

    // MARK: - Helpers

    public func hitTest(_ point: GraphPoint) -> GraphNodeID? {
        if let id = layout.hitTest(point, camera: camera, viewSize: viewSize, radius: Self.tapSlop) { return id }
        // Hubs are bigger targets.
        guard let hubHit = layout.hitTest(point, camera: camera, viewSize: viewSize, radius: Self.hubSlop * max(camera.zoom, 0.6)),
              nodesByID[hubHit]?.isHub == true else { return nil }
        return hubHit
    }
}
