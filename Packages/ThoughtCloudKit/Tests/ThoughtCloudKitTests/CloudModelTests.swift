import Foundation
import Testing
@testable import ThoughtCloudKit

@MainActor
@Suite("Cloud model")
struct CloudModelTests {
    let viewSize = GraphPoint(390, 700)
    let a = GraphNodeID.item(UUID())
    let b = GraphNodeID.item(UUID())
    let c = GraphNodeID.item(UUID())
    let hub = GraphNodeID.category(UUID())

    func makeModel() -> CloudModel {
        let graph = CloudGraph(
            nodes: [.hub(hub), .leaf(a), .leaf(b), .leaf(c)],
            edges: [GraphEdge(a: hub, b: a, kind: .membership), GraphEdge(a: hub, b: b, kind: .membership), GraphEdge(a: a, b: b, kind: .link)]
        )
        let model = CloudModel(seed: 1)
        model.setViewSize(viewSize)
        model.update(graph: graph)
        return model
    }

    func screen(_ model: CloudModel, _ id: GraphNodeID) -> GraphPoint {
        model.camera.toScreen(model.layout.position(of: id)!, viewSize: viewSize)
    }

    @Test func firstLoadFitsEverythingOnScreen() {
        let model = makeModel()
        for id in [a, b, c, hub] {
            let p = screen(model, id)
            #expect(p.x > 0 && p.x < viewSize.x && p.y > 0 && p.y < viewSize.y)
        }
    }

    @Test func tappingANodeSelectsItAndHighlightsNeighbours() {
        let model = makeModel()
        model.tap(at: screen(model, a))
        #expect(model.selection == a)
        #expect(model.highlighted == [a, b, hub])
    }

    @Test func tappingEmptySpaceClearsSelection() {
        let model = makeModel()
        model.select(a)
        model.tap(at: GraphPoint(-500, -500))
        #expect(model.selection == nil)
        #expect(model.highlighted.isEmpty)
    }

    @Test func draggingEmptySpacePansTheCamera() {
        let model = makeModel()
        let before = model.camera.center
        model.dragChanged(start: GraphPoint(5, 5), location: GraphPoint(45, 5))
        model.dragEnded()
        #expect(model.camera.center.x < before.x)
    }

    @Test func draggingANodeMovesItAndReleasesIt() {
        let model = makeModel()
        let start = screen(model, c)
        let target = start + GraphPoint(60, 40)
        model.dragChanged(start: start, location: target)
        let p = screen(model, c)
        #expect(abs(p.x - target.x) < 1 && abs(p.y - target.y) < 1)
        model.dragEnded()
        #expect(model.draggingNode == nil)
    }

    @Test func pinchingZoomsAroundTheFingers() {
        let model = makeModel()
        let zoom = model.camera.zoom
        model.pinch(by: 2, anchor: GraphPoint(100, 100))
        #expect(abs(model.camera.zoom - min(zoom * 2, GraphCamera.maxZoom)) < 1e-9)
    }

    @Test func zoomButtonsApplyImmediatelyWithoutWaitingForATick() {
        let model = makeModel()
        model.settleNow()
        let zoom = model.camera.zoom
        let center = model.camera.center
        model.zoom(by: 1.4)
        #expect(abs(model.camera.zoom - zoom * 1.4) < 1e-9)
        #expect(!model.needsAnimation)
        model.zoom(by: 1 / 1.4)
        #expect(abs(model.camera.zoom - zoom) < 1e-9)
        let d = model.camera.center - center
        #expect((d * d).sum() < 1e-9)
    }

    @Test func zoomButtonCancelsAnInFlightCameraFlight() {
        let model = makeModel()
        model.select(c)
        let zoom = model.camera.zoom
        model.zoom(by: 1.4)
        #expect(abs(model.camera.zoom - min(zoom * 1.4, GraphCamera.maxZoom)) < 1e-9)
        for _ in 0..<60 { model.tick() }
        #expect(abs(model.camera.zoom - min(zoom * 1.4, GraphCamera.maxZoom)) < 1e-9)
    }

    @Test func selectingFliesTheCameraToTheNodeAboveTheSheet() {
        let model = makeModel()
        model.select(c)
        for _ in 0..<120 { model.tick() }
        let p = screen(model, c)
        #expect(abs(p.x - viewSize.x / 2) < 2)
        #expect(p.y < viewSize.y / 2)
        #expect(model.camera.zoom >= CloudModel.focusZoom - 1e-6)
    }

    @Test func updatingTheGraphDropsASelectionThatNoLongerExists() {
        let model = makeModel()
        model.select(c)
        model.update(graph: CloudGraph(nodes: [.leaf(a)], edges: []))
        #expect(model.selection == nil)
    }

    @Test func needsAnimationUntilSettled() {
        let model = makeModel()
        model.settleNow()
        #expect(!model.needsAnimation)
        model.select(a)
        #expect(model.needsAnimation)
    }
}
