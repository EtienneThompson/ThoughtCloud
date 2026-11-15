import SwiftUI
import ThoughtCloudKit

/// The panel that slides up when a node is tapped in the Cloud.
struct NodeSheet: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    let node: GraphNode
    let cloud: CloudModel
    let openCategory: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(Color(white: 0.3)).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            switch node.id {
            case .item(let id):
                if let item = library.item(id) { itemContent(item) }
            case .subtask(let todoID, let subtaskID):
                if let todo = library.item(todoID), let subtask = todo.subtasks.first(where: { $0.id == subtaskID }) {
                    subtaskContent(subtask, of: todo)
                }
            case .category(let id):
                if let category = library.category(id) {
                    hubContent(title: "\(category.emoji) \(category.name)", color: Color(hex: category.colorHex), items: library.items(inCategory: id), categoryID: id)
                }
            case .inbox:
                hubContent(title: "📥 Inbox", color: Color(hex: CategoryPalette.inboxHex),
                           items: library.items.filter { !$0.isArchived && library.style(for: $0) == .inbox }, categoryID: nil)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(Color(hex: "#1C1C24"), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .topTrailing) {
            Button { cloud.select(nil) } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
                    .frame(width: 28, height: 28).background(Theme.card2, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .shadow(color: .black.opacity(0.5), radius: 20, y: -6)
    }

    // MARK: - Item

    @ViewBuilder
    private func itemContent(_ item: Item) -> some View {
        let style = library.style(for: item)
        HStack(spacing: 6) {
            KindPill(kind: item.kind)
            CategoryPills(style: style, compact: true)
        }
        Text(item.displayTitle).font(.title3.weight(.semibold)).lineLimit(3)
        Text(detail(for: item)).font(.footnote).foregroundStyle(Theme.dim)
        linked
        HStack(spacing: 8) {
            switch item.kind {
            case .todo:
                action(item.isCompleted ? "Reopen" : "Mark done", primary: style.primary) { library.toggleCompleted(item.id) }
            case .thought:
                action("→ Todo", primary: ItemKind.todo.color) { if let new = library.promote(item.id, to: .todo) { reselect(new.id) } }
                action("→ Review") { if let new = library.promote(item.id, to: .review) { reselect(new.id) } }
            case .review, .event:
                if node.isDue {
                    action("Got it", primary: Theme.success) { library.grade(item.id, .gotIt) }
                    action("Again") { library.grade(item.id, .again) }
                }
            }
            action("Open") { app.detailItemID = item.id }
        }
    }

    // MARK: - Subtask

    @ViewBuilder
    private func subtaskContent(_ subtask: Subtask, of todo: Item) -> some View {
        let style = library.style(for: todo)
        HStack(spacing: 6) {
            Text("Subtask").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            CategoryPills(style: style, compact: true)
        }
        Text(subtask.title).font(.title3.weight(.semibold)).lineLimit(3)
            .strikethrough(subtask.isCompleted)
        Text(subtask.isCompleted ? "Done" : "Open").font(.footnote).foregroundStyle(Theme.dim)
        linked
        HStack(spacing: 8) {
            action(subtask.isCompleted ? "Reopen" : "Mark done", primary: style.primary) { library.toggleSubtask(todo.id, subtask.id) }
            action("Open todo") { app.detailItemID = todo.id }
        }
    }

    private func reselect(_ id: UUID) {
        DispatchQueue.main.async { cloud.select(.item(id)) }
    }

    private func detail(for item: Item) -> String {
        switch item.kind {
        case .todo:
            let progress = item.subtaskProgress
            let steps = progress.total > 0 ? " · \(progress.done)/\(progress.total) subtasks" : ""
            if item.isCompleted { return "Done" + steps }
            guard let due = item.dueDate else { return "No due date · someday" + steps }
            return (node.isOverdue ? "Overdue · " : "Due ") + due.shortRelative(includeTime: item.dueHasTime) + steps
        case .thought:
            return "Captured " + item.createdAt.shortRelative(includeTime: false)
        case .review:
            guard let state = item.review else { return "" }
            var text = node.isDue ? "Due for review now" : "Next review " + state.nextReviewAt.shortRelative(includeTime: false)
            if let until = state.rememberUntil { text += " · until " + until.shortRelative(includeTime: false) }
            return text + " · seen \(state.seenCount)×"
        case .event:
            guard let event = item.event else { return "" }
            return event.whenText + " · " + event.countdownText(now: library.now, calendar: library.calendar)
        }
    }

    // MARK: - Hub

    @ViewBuilder
    private func hubContent(title: String, color: Color, items: [Item], categoryID: UUID?) -> some View {
        Text(title).font(.title3.weight(.semibold)).foregroundStyle(color)
        let counts = ItemKind.allCases.map { kind in "\(items.filter { $0.kind == kind }.count) \(kind.plural.lowercased())" }
        Text(counts.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.dim)
        linked
        HStack(spacing: 8) {
            if let categoryID {
                action("Open category", primary: color) { cloud.select(nil); openCategory(categoryID) }
                action("Review deck") { cloud.select(nil); app.openReview(category: categoryID) }
            }
            action("Capture here") { app.presentCapture(categoryIDs: categoryID.map { [$0] } ?? []) }
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private var linked: some View {
        let neighbors = cloud.graph.neighbors(of: node.id).compactMap { cloud.nodesByID[$0] }
            .sorted { $0.isHub && !$1.isHub }
        if !neighbors.isEmpty {
            Text("LINKED").font(.caption2.weight(.semibold)).foregroundStyle(Theme.dim).padding(.top, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(neighbors.prefix(12)) { neighbor in
                        Button { cloud.select(neighbor.id) } label: {
                            Text(chipTitle(neighbor))
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(Theme.card2, in: Capsule())
                                .foregroundStyle(chipColor(neighbor))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func chipTitle(_ node: GraphNode) -> String {
        if case .hub(let emoji, _) = node.role { return "\(emoji) \(node.label)" }
        return node.label.count > 26 ? String(node.label.prefix(25)) + "…" : node.label
    }

    private func chipColor(_ node: GraphNode) -> Color {
        switch node.role {
        case .hub(_, let hex): Color(hex: hex)
        case .item(_, let style), .subtask(let style): style.primary
        }
    }

    private func action(_ title: String, primary: Color? = nil, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(primary ?? Theme.card2, in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(primary == nil ? Theme.text : .black)
        }
        .buttonStyle(.plain)
    }
}
