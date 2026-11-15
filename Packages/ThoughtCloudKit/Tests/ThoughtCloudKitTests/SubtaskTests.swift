import Foundation
import Testing
@testable import ThoughtCloudKit

@MainActor
@Suite("Subtasks")
struct SubtaskTests {
    let clock = FakeClock(day(10, hour: 9))
    let persistence = SpyPersistence()
    let library: Library

    init() {
        library = Library(persistence: persistence, dates: clock, calendar: .testUTC)
    }

    // MARK: Library

    @Test func newTodosHaveNoSubtasks() {
        let todo = library.add(kind: .todo, title: "Move flat")
        #expect(todo.subtasks.isEmpty)
    }

    @Test func anyNumberOfSubtasksCanBeAddedInOrderAndArePersisted() {
        let todo = library.add(kind: .todo, title: "Move flat")
        for title in ["Book van", "Pack kitchen", "Forward mail", "Return keys", "Clean oven"] {
            library.addSubtask(to: todo.id, title: title)
        }
        #expect(library.item(todo.id)?.subtasks.map(\.title) == ["Book van", "Pack kitchen", "Forward mail", "Return keys", "Clean oven"])
        #expect(persistence.stored.items.first?.subtasks.count == 5)
    }

    @Test func blankSubtaskTitlesAreIgnoredAndTitlesAreTrimmed() {
        let todo = library.add(kind: .todo, title: "Move flat")
        #expect(library.addSubtask(to: todo.id, title: "   ") == nil)
        library.addSubtask(to: todo.id, title: "  Book van \n")
        #expect(library.item(todo.id)?.subtasks.map(\.title) == ["Book van"])
    }

    @Test func subtasksCanBeCompletedReopenedRenamedAndDeleted() throws {
        let todo = library.add(kind: .todo, title: "Move flat")
        let van = try #require(library.addSubtask(to: todo.id, title: "Book van"))
        let keys = try #require(library.addSubtask(to: todo.id, title: "Return keys"))

        library.toggleSubtask(todo.id, van.id)
        #expect(library.item(todo.id)?.subtasks.first?.completedAt == day(10, hour: 9))
        library.toggleSubtask(todo.id, van.id)
        #expect(library.item(todo.id)?.subtasks.first?.isCompleted == false)

        library.renameSubtask(todo.id, keys.id, title: "Return both keys")
        #expect(library.item(todo.id)?.subtasks.last?.title == "Return both keys")

        library.deleteSubtask(todo.id, van.id)
        #expect(library.item(todo.id)?.subtasks.map(\.id) == [keys.id])
    }

    @Test func subtasksCanBeReordered() throws {
        let todo = library.add(kind: .todo, title: "Move flat")
        let a = try #require(library.addSubtask(to: todo.id, title: "a"))
        let b = try #require(library.addSubtask(to: todo.id, title: "b"))
        let c = try #require(library.addSubtask(to: todo.id, title: "c"))
        library.moveSubtasks(todo.id, from: IndexSet(integer: 2), to: 0)
        #expect(library.item(todo.id)?.subtasks.map(\.id) == [c.id, a.id, b.id])
    }

    @Test func progressCountsDoneSubtasks() throws {
        let todo = library.add(kind: .todo, title: "Move flat")
        let a = try #require(library.addSubtask(to: todo.id, title: "a"))
        library.addSubtask(to: todo.id, title: "b")
        library.toggleSubtask(todo.id, a.id)
        let item = try #require(library.item(todo.id))
        #expect(item.subtaskProgress == SubtaskProgress(done: 1, total: 2))
    }

    // MARK: Persistence

    @Test func itemsSavedBeforeSubtasksExistedStillLoad() throws {
        let todo = Item(kind: .todo, title: "Old", createdAt: day(1))
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder.library.encode(todo)) as? [String: Any])
        json.removeValue(forKey: "subtasks")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder.library.decode(Item.self, from: data)
        #expect(decoded.subtasks.isEmpty)
        #expect(decoded.title == "Old")
    }

    @Test func subtasksRoundTripThroughJSON() throws {
        var todo = Item(kind: .todo, title: "New", createdAt: day(1))
        todo.subtasks = [Subtask(title: "step", createdAt: day(1))]
        let decoded = try JSONDecoder.library.decode(Item.self, from: JSONEncoder.library.encode(todo))
        #expect(decoded == todo)
    }

    // MARK: Cloud

    @Test func subtasksAppearInTheCloudAttachedOnlyToTheirTodo() throws {
        let todo = library.add(kind: .todo, title: "Move flat")
        let van = try #require(library.addSubtask(to: todo.id, title: "Book van"))
        let keys = try #require(library.addSubtask(to: todo.id, title: "Return keys"))
        let graph = GraphBuilder.build(from: library)

        for sub in [van, keys] {
            let id = GraphNodeID.subtask(todo: todo.id, subtask: sub.id)
            #expect(graph.node(id)?.label == sub.title)
            let edges = graph.edges.filter { $0.touches(id) }
            #expect(edges == [GraphEdge(a: .item(todo.id), b: id, kind: .subtask)])
        }
    }

    @Test func doneSubtasksAreFadedOrHiddenWithCompleted() throws {
        let todo = library.add(kind: .todo, title: "Move flat")
        let van = try #require(library.addSubtask(to: todo.id, title: "Book van"))
        library.toggleSubtask(todo.id, van.id)
        let id = GraphNodeID.subtask(todo: todo.id, subtask: van.id)
        #expect(GraphBuilder.build(from: library).node(id)?.isFaded == true)
        #expect(GraphBuilder.build(from: library, options: GraphOptions(showCompleted: false)).node(id) == nil)
    }

    @Test func subtasksDisappearWithTheirTodo() throws {
        let todo = library.add(kind: .todo, title: "Move flat")
        library.addSubtask(to: todo.id, title: "Book van")
        library.setArchived(todo.id, true)
        #expect(!GraphBuilder.build(from: library).nodes.contains { $0.isSubtask })
        library.setArchived(todo.id, false)
        #expect(GraphBuilder.build(from: library, options: GraphOptions(kinds: [.thought])).nodes.allSatisfy { !$0.isSubtask })
    }

    @Test func subtasksOfItemsThatAreNoLongerTodosAreNotShown() {
        let todo = library.add(kind: .todo, title: "Move flat")
        library.addSubtask(to: todo.id, title: "Book van")
        library.setKind(todo.id, .thought)
        #expect(!GraphBuilder.build(from: library).nodes.contains { $0.isSubtask })
        #expect(library.item(todo.id)?.subtasks.count == 1)
    }

    @Test func subtasksClusterTightlyAroundTheirTodo() throws {
        let work = library.createCategory(name: "Work")
        let todo = library.add(kind: .todo, title: "Launch", categoryIDs: [work.id])
        for i in 0..<6 { library.addSubtask(to: todo.id, title: "step \(i)") }
        library.add(kind: .todo, title: "Other", categoryIDs: [work.id])
        let graph = GraphBuilder.build(from: library)
        var layout = ForceLayout(seed: 7)
        layout.sync(with: graph)
        layout.settle(maxSteps: 3000)

        let parent = try #require(layout.position(of: .item(todo.id)))
        let hub = try #require(layout.position(of: .category(work.id)))
        func dist(_ a: GraphPoint, _ b: GraphPoint) -> Double { let d = a - b; return (d * d).sum().squareRoot() }
        let hubDistance = dist(parent, hub)
        for node in graph.nodes where node.isSubtask {
            let p = try #require(layout.position(of: node.id))
            #expect(dist(p, parent) < hubDistance)
        }
    }
}
