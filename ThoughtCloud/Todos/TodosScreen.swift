import SwiftUI
import ThoughtCloudKit

struct TodosScreen: View {
    enum Grouping: String { case date, category }

    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    @State private var filter: UUID?
    @AppStorage("todos.grouping") private var grouping: Grouping = .date

    private let sectioner = TodoSectioner()

    var body: some View {
        NavigationStack {
            let todos = filtered
            List {
                Section {
                    CategoryFilterBar(categories: library.categories, selection: $filter, counts: openCounts)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if todos.isEmpty {
                    EmptyStateView(symbol: "checkmark.circle", title: "Nothing to do")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(sections(for: todos), id: \.title) { section in
                        Section {
                            ForEach(section.items) { item in
                                TodoRow(item: item, overdue: sectioner.isOverdue(item, now: library.now))
                            }
                        } header: {
                            Text(section.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(section.color ?? Theme.dim)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Todos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Group by", selection: $grouping) {
                            Text("Date").tag(Grouping.date)
                            Text("Category").tag(Grouping.category)
                        }
                    } label: {
                        Label("Group: \(grouping == .date ? "Date" : "Category")", systemImage: "line.3.horizontal.decrease")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private var filtered: [Item] {
        library.activeItems(of: .todo).filter { filter == nil || $0.categoryIDs.contains(filter!) }
    }

    private var openCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for item in library.activeItems(of: .todo) where !item.isCompleted {
            for id in item.categoryIDs { counts[id, default: 0] += 1 }
        }
        return counts
    }

    private struct DisplaySection {
        var title: String
        var color: Color?
        var items: [Item]
    }

    private func sections(for todos: [Item]) -> [DisplaySection] {
        let dated = sectioner.sections(for: todos, now: library.now)
        switch grouping {
        case .date:
            return dated.map { DisplaySection(title: $0.kind.title, items: $0.items) }
        case .category:
            let open = todos.filter { !$0.isCompleted }
            var result: [DisplaySection] = library.categories.compactMap { category in
                let items = open.filter { $0.categoryIDs.contains(category.id) }
                return items.isEmpty ? nil : DisplaySection(title: "\(category.emoji) \(category.name)", color: Color(hex: category.colorHex), items: sortByDue(items))
            }
            let inbox = open.filter { library.style(for: $0) == .inbox }
            if !inbox.isEmpty { result.append(DisplaySection(title: "📥 Inbox", items: sortByDue(inbox))) }
            if let done = dated.first(where: { $0.kind == .done }) { result.append(DisplaySection(title: "Done", items: done.items)) }
            return result
        }
    }

    private func sortByDue(_ items: [Item]) -> [Item] {
        items.sorted { ($0.dueDate ?? .distantFuture, $1.createdAt) < ($1.dueDate ?? .distantFuture, $0.createdAt) }
    }
}

struct TodoRow: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    let item: Item
    var overdue = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.snappy) { library.toggleCompleted(item.id) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isCompleted ? ItemKind.todo.color : Theme.dim)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: item.isCompleted) { _, new in new }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Theme.dim : Theme.text)
                HStack(spacing: 6) {
                    CategoryPills(style: library.style(for: item), compact: true)
                    if let due = item.dueDate, !item.isCompleted {
                        Text(overdue ? "Overdue · " + due.shortRelative(includeTime: item.dueHasTime) : due.shortRelative(includeTime: item.dueHasTime))
                            .font(.caption)
                            .foregroundStyle(overdue ? Theme.danger : Theme.dim)
                    }
                    if !library.linkedItems(of: item.id).isEmpty {
                        Image(systemName: "link").font(.caption2).foregroundStyle(Theme.dim)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.detailItemID = item.id }
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.line)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { library.toggleCompleted(item.id) } label: { Label(item.isCompleted ? "Reopen" : "Done", systemImage: "checkmark") }
                .tint(Theme.success)
            if !item.isCompleted {
                Button {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
                    library.setDueDate(item.id, tomorrow, hasTime: false)
                } label: { Label("Tomorrow", systemImage: "arrow.forward") }
                    .tint(.orange)
            }
        }
        .swipeActions(edge: .leading) {
            Button(role: .destructive) { library.delete(item.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
