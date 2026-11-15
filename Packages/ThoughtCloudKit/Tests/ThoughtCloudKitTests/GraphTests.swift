import Foundation
import Testing
@testable import ThoughtCloudKit

@MainActor
@Suite("Graph builder")
struct GraphBuilderTests {
    let clock = FakeClock(day(10, hour: 9))
    let library: Library

    init() {
        library = Library(persistence: InMemoryPersistence(), dates: clock, calendar: .testUTC)
    }

    func build(_ options: GraphOptions = GraphOptions()) -> CloudGraph {
        GraphBuilder.build(from: library, options: options)
    }

    @Test func everyCategoryIsAHubAndItemsConnectToEachOfTheirCategories() {
        let work = library.createCategory(name: "Work")
        let travel = library.createCategory(name: "Travel")
        let item = library.add(kind: .todo, title: "Book flights", categoryIDs: [travel.id, work.id])
        let graph = build()
        #expect(graph.node(.category(work.id))?.isHub == true)
        let memberships = graph.edges.filter { $0.kind == .membership && $0.touches(.item(item.id)) }
        #expect(Set(memberships.map { $0.other(than: .item(item.id)) }) == [.category(work.id), .category(travel.id)])
    }

    @Test func uncategorisedItemsHangOffAnInboxHubThatOnlyExistsWhenNeeded() {
        #expect(build().node(.inbox) == nil)
        let item = library.add(kind: .thought, title: "e-bikes")
        let graph = build()
        #expect(graph.node(.inbox) != nil)
        #expect(graph.edges.contains { $0.touches(.inbox) && $0.touches(.item(item.id)) })
    }

    @Test func userLinksBecomeEdges() {
        let a = library.add(kind: .thought, title: "a")
        let b = library.add(kind: .thought, title: "b")
        library.link(a.id, b.id)
        #expect(build().edges.contains { $0.kind == .link && $0.touches(.item(a.id)) && $0.touches(.item(b.id)) })
    }

    @Test func archivedItemsAndTheirLinksAreHidden() {
        let a = library.add(kind: .thought, title: "a")
        let b = library.add(kind: .thought, title: "b")
        library.link(a.id, b.id)
        library.setArchived(a.id, true)
        let graph = build()
        #expect(graph.node(.item(a.id)) == nil)
        #expect(!graph.edges.contains { $0.touches(.item(a.id)) })
    }

    @Test func completedTodosAreFadedOrHiddenByOption() {
        let todo = library.add(kind: .todo, title: "done")
        library.toggleCompleted(todo.id)
        #expect(build().node(.item(todo.id))?.isFaded == true)
        #expect(build(GraphOptions(showCompleted: false)).node(.item(todo.id)) == nil)
    }

    @Test func flagsDueReviewsAndOverdueTodos() {
        let review = library.add(kind: .review, title: "r")
        let todo = library.add(kind: .todo, title: "t", date: DetectedDate(date: day(8), hasTime: false, matchedText: ""))
        let graph = build()
        #expect(graph.node(.item(review.id))?.isDue == true)
        #expect(graph.node(.item(todo.id))?.isOverdue == true)
    }

    @Test func kindFilterHidesOtherKinds() {
        let t = library.add(kind: .todo, title: "t")
        let h = library.add(kind: .thought, title: "h")
        let graph = build(GraphOptions(kinds: [.thought]))
        #expect(graph.node(.item(t.id)) == nil)
        #expect(graph.node(.item(h.id)) != nil)
    }
}

@Suite("Force layout")
struct ForceLayoutTests {
    /// Two clusters: hub A with 4 items, hub B with 4 items.
    func twoClusters() -> CloudGraph {
        let a = GraphNodeID.category(UUID()), b = GraphNodeID.category(UUID())
        var nodes = [GraphNode.hub(a), GraphNode.hub(b)]
        var edges: [GraphEdge] = []
        for hub in [a, b] {
            for _ in 0..<4 {
                let id = GraphNodeID.item(UUID())
                nodes.append(.leaf(id))
                edges.append(GraphEdge(a: hub, b: id, kind: .membership))
            }
        }
        return CloudGraph(nodes: nodes, edges: edges)
    }

    func distance(_ layout: ForceLayout, _ a: GraphNodeID, _ b: GraphNodeID) -> Double {
        let d = layout.position(of: a)! - layout.position(of: b)!
        return (d * d).sum().squareRoot()
    }

    @Test func connectedNodesEndUpCloserThanUnconnectedOnes() {
        let graph = twoClusters()
        var layout = ForceLayout(seed: 1)
        layout.sync(with: graph)
        layout.settle(maxSteps: 400)
        let leafA = graph.edges[0].b, hubA = graph.edges[0].a
        let leafB = graph.edges[4].b
        #expect(distance(layout, leafA, hubA) < distance(layout, leafA, leafB))
    }

    @Test func positionsStayFinite() {
        var layout = ForceLayout(seed: 2)
        layout.sync(with: twoClusters())
        layout.settle(maxSteps: 400)
        #expect(layout.positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test func itSettles() {
        var layout = ForceLayout(seed: 3)
        layout.sync(with: twoClusters())
        layout.settle(maxSteps: 2000)
        #expect(layout.isSettled)
    }

    @Test func pinnedNodesStayWhereTheyArePut() {
        let graph = twoClusters()
        var layout = ForceLayout(seed: 4)
        layout.sync(with: graph)
        let id = graph.nodes[3].id
        layout.pin(id, at: GraphPoint(500, -200))
        for _ in 0..<50 { layout.step() }
        #expect(layout.position(of: id) == GraphPoint(500, -200))
        layout.unpin(id)
        layout.step()
        #expect(layout.position(of: id) != GraphPoint(500, -200))
    }

    @Test func syncKeepsExistingPositionsAndPlacesNewNodesNearTheirNeighbour() {
        var graph = twoClusters()
        var layout = ForceLayout(seed: 5)
        layout.sync(with: graph)
        layout.settle(maxSteps: 400)
        let before = layout.positions
        let hub = graph.nodes[0].id
        let newID = GraphNodeID.item(UUID())
        graph.nodes.append(.leaf(newID))
        graph.edges.append(GraphEdge(a: hub, b: newID, kind: .membership))
        layout.sync(with: graph)
        for (id, point) in before { #expect(layout.position(of: id) == point) }
        #expect(distance(layout, newID, hub) < 40)
    }

    @Test func removedNodesAreDropped() {
        var graph = twoClusters()
        var layout = ForceLayout(seed: 6)
        layout.sync(with: graph)
        let removed = graph.nodes.removeLast().id
        graph.edges.removeAll { $0.touches(removed) }
        layout.sync(with: graph)
        #expect(layout.position(of: removed) == nil)
    }

    @Test func sameSeedSameLayout() {
        let graph = twoClusters()
        var a = ForceLayout(seed: 9), b = ForceLayout(seed: 9)
        a.sync(with: graph); b.sync(with: graph)
        a.settle(maxSteps: 100); b.settle(maxSteps: 100)
        #expect(a.positions == b.positions)
    }
}

@Suite("Graph camera")
struct GraphCameraTests {
    let viewSize = GraphPoint(300, 600)

    @Test func screenAndWorldRoundTrip() {
        let camera = GraphCamera(center: GraphPoint(40, -20), zoom: 1.7)
        let world = GraphPoint(123, 45)
        let back = camera.toWorld(camera.toScreen(world, viewSize: viewSize), viewSize: viewSize)
        #expect(abs(back.x - world.x) < 1e-9 && abs(back.y - world.y) < 1e-9)
    }

    @Test func centerIsInTheMiddleOfTheView() {
        let camera = GraphCamera(center: GraphPoint(10, 10), zoom: 2)
        #expect(camera.toScreen(GraphPoint(10, 10), viewSize: viewSize) == GraphPoint(150, 300))
    }

    @Test func zoomingKeepsTheAnchorUnderTheFinger() {
        var camera = GraphCamera(center: .zero, zoom: 1)
        let anchor = GraphPoint(220, 100)
        let worldUnderFinger = camera.toWorld(anchor, viewSize: viewSize)
        camera.zoom(by: 2.5, anchor: anchor, viewSize: viewSize)
        let after = camera.toWorld(anchor, viewSize: viewSize)
        #expect(abs(after.x - worldUnderFinger.x) < 1e-9 && abs(after.y - worldUnderFinger.y) < 1e-9)
        #expect(camera.zoom == 2.5)
    }

    @Test func zoomIsClamped() {
        var camera = GraphCamera(center: .zero, zoom: 1)
        camera.zoom(by: 100, anchor: .zero, viewSize: viewSize)
        #expect(camera.zoom == GraphCamera.maxZoom)
        camera.zoom(by: 0.0001, anchor: .zero, viewSize: viewSize)
        #expect(camera.zoom == GraphCamera.minZoom)
    }

    @Test func panningMovesTheWorldWithTheFinger() {
        var camera = GraphCamera(center: .zero, zoom: 2)
        camera.pan(byScreen: GraphPoint(20, -10))
        #expect(camera.center == GraphPoint(-10, 5))
    }

    @Test func fitShowsTheWholeBounds() {
        let camera = GraphCamera.fitting(min: GraphPoint(-100, -50), max: GraphPoint(100, 250), viewSize: viewSize, padding: 0)
        #expect(camera.center == GraphPoint(0, 100))
        #expect(camera.zoom == 1.5)
    }

    @Test func labelsFadeInWhenZoomedIn() {
        #expect(GraphCamera(center: .zero, zoom: 0.8).labelOpacity == 0)
        #expect(GraphCamera(center: .zero, zoom: 3).labelOpacity == 1)
        let mid = GraphCamera(center: .zero, zoom: (GraphCamera.labelFadeStart + GraphCamera.labelFadeEnd) / 2).labelOpacity
        #expect(mid > 0 && mid < 1)
    }

    @Test func hitTestingFindsTheNearestNodeWithinReach() {
        var layout = ForceLayout(seed: 1)
        let a = GraphNodeID.item(UUID()), b = GraphNodeID.item(UUID())
        layout.sync(with: CloudGraph(nodes: [.leaf(a), .leaf(b)], edges: []))
        layout.pin(a, at: GraphPoint(0, 0))
        layout.pin(b, at: GraphPoint(100, 0))
        let camera = GraphCamera(center: .zero, zoom: 1)
        let screenA = camera.toScreen(.zero, viewSize: viewSize)
        #expect(layout.hitTest(screenA + GraphPoint(5, 5), camera: camera, viewSize: viewSize, radius: 20) == a)
        #expect(layout.hitTest(screenA + GraphPoint(50, 0), camera: camera, viewSize: viewSize, radius: 20) == nil)
    }
}
