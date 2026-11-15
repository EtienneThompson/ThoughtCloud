import SwiftUI
import ThoughtCloudKit

struct ThoughtsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    @State private var filter: UUID?
    @State private var search = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CategoryFilterBar(categories: library.categories, selection: $filter, counts: counts)
                    let thoughts = filtered
                    if thoughts.isEmpty {
                        EmptyStateView(symbol: "lightbulb", title: search.isEmpty ? "No thoughts yet" : "No matches")
                    } else {
                        masonry(thoughts).padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Thoughts")
            .searchable(text: $search, prompt: "Search thoughts")
        }
    }

    private var filtered: [Item] {
        library.activeItems(of: .thought)
            .filter { filter == nil || $0.categoryIDs.contains(filter!) }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var counts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for item in library.activeItems(of: .thought) {
            for id in item.categoryIDs { counts[id, default: 0] += 1 }
        }
        return counts
    }

    /// Two columns, each card goes to the currently shorter column.
    private func masonry(_ items: [Item]) -> some View {
        var left: [Item] = [], right: [Item] = []
        var leftHeight = 0, rightHeight = 0
        for item in items {
            let estimate = 60 + item.displayTitle.count + min(item.body.count, 140)
            if leftHeight <= rightHeight { left.append(item); leftHeight += estimate } else { right.append(item); rightHeight += estimate }
        }
        return HStack(alignment: .top, spacing: 10) {
            LazyVStack(spacing: 10) { ForEach(left) { ThoughtCard(item: $0) } }
            LazyVStack(spacing: 10) { ForEach(right) { ThoughtCard(item: $0) } }
        }
    }
}

struct ThoughtCard: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    let item: Item

    var body: some View {
        let style = library.style(for: item)
        VStack(alignment: .leading, spacing: 6) {
            Text(style.emojis).font(.subheadline)
            Text(item.displayTitle).font(.subheadline).foregroundStyle(Theme.text)
            if !item.body.isEmpty {
                Text(item.body).font(.caption).foregroundStyle(Theme.dim).lineLimit(4)
            }
            HStack {
                Text(item.createdAt.shortRelative(includeTime: false))
                Spacer()
                if !library.linkedItems(of: item.id).isEmpty { Image(systemName: "link") }
                Text(style.categories.count >= 3 ? "\(style.categories.count) categories" : style.label)
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(Theme.dim)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.primary.opacity(0.09).blendMode(.plusLighter))
        .background(Theme.card)
        .overlay(alignment: .top) { CategoryStripe(style: style) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { app.detailItemID = item.id }
        .contextMenu {
            Button("Turn into Todo", systemImage: ItemKind.todo.symbol) { library.promote(item.id, to: .todo) }
            Button("Turn into Review card", systemImage: ItemKind.review.symbol) { library.promote(item.id, to: .review) }
            Divider()
            Button("Archive", systemImage: "archivebox") { library.setArchived(item.id, true) }
            Button("Delete", systemImage: "trash", role: .destructive) { library.delete(item.id) }
        }
    }
}
