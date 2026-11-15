import SwiftUI
import ThoughtCloudKit

struct CategoryScreen: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    let categoryID: UUID
    @State private var editing = false

    var body: some View {
        if let category = library.category(categoryID) {
            content(category)
        } else {
            EmptyStateView(symbol: "tag", title: "Category deleted")
        }
    }

    private func content(_ category: ItemCategory) -> some View {
        let color = Color(hex: category.colorHex)
        let items = library.items(inCategory: categoryID)
        let todos = items.filter { $0.kind == .todo && !$0.isCompleted }
        let thoughts = items.filter { $0.kind == .thought }.sorted { $0.createdAt > $1.createdAt }
        let reviews = items.filter { $0.kind == .review }
        let events = items.filter { $0.kind == .event && $0.event != nil }.sorted { $0.event!.start < $1.event!.start }
        let due = library.dueReviews(inCategory: categoryID).count

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Text(category.emoji).font(.system(size: 30))
                        .frame(width: 56, height: 56)
                        .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading) {
                        Text(category.name).font(.title.weight(.bold)).foregroundStyle(color)
                        Text("\(items.count) items" + (due > 0 ? " · \(due) due" : "")).font(.footnote).foregroundStyle(Theme.dim)
                    }
                }
                mixBar(todos: items.filter { $0.kind == .todo }.count, thoughts: thoughts.count, reviews: reviews.count, events: events.count)

                Button { app.openReview(category: categoryID) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Review \(category.name) deck").font(.headline)
                            Text(due > 0 ? "\(due) of \(reviews.count) cards due" : "\(reviews.count) cards · none due").font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "play.fill").foregroundStyle(.black).frame(width: 34, height: 34).background(ItemKind.review.color, in: Circle())
                    }
                    .padding(14)
                    .background(LinearGradient(colors: [Color(hex: "#3A2C5C"), Color(hex: "#231B38")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                section("Todos", count: todos.count) {
                    ForEach(todos) { item in
                        CompactTodoRow(item: item)
                    }
                }
                section("Events", count: events.count) {
                    ForEach(events) { EventRow(item: $0) }
                }
                section("Thoughts", count: thoughts.count) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(thoughts) { ThoughtCard(item: $0).frame(width: 170) }
                        }
                    }
                    .scrollClipDisabled()
                }
                section("Review cards", count: reviews.count) {
                    ForEach(reviews) { item in
                        Button { app.detailItemID = item.id } label: {
                            HStack {
                                Image(systemName: "diamond.fill").font(.caption).foregroundStyle(color)
                                Text(item.displayTitle).foregroundStyle(Theme.text)
                                Spacer()
                                if let next = item.review?.nextReviewAt {
                                    Text(next <= Date() ? "due" : next.shortRelative(includeTime: false)).font(.caption).foregroundStyle(Theme.dim)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { app.presentCapture(categoryIDs: [categoryID]) }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { CategoryEditor(category: category) }
        }
    }

    private func mixBar(todos: Int, thoughts: Int, reviews: Int, events: Int) -> some View {
        let total = max(1, todos + thoughts + reviews + events)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach([(ItemKind.todo, todos), (.event, events), (.thought, thoughts), (.review, reviews)], id: \.0) { kind, count in
                        if count > 0 {
                            kind.color.frame(width: max(4, (geo.size.width - 4) * CGFloat(count) / CGFloat(total)))
                        }
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            HStack(spacing: 12) {
                ForEach([(ItemKind.todo, todos), (.event, events), (.thought, thoughts), (.review, reviews)], id: \.0) { kind, count in
                    Label("\(count) \(kind.plural.lowercased())", systemImage: "circle.fill")
                        .labelStyle(DotLabelStyle(color: kind.color))
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.dim)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                content()
            }
        }
    }
}

struct DotLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
    }
}

struct CompactTodoRow: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            Button { withAnimation { library.toggleCompleted(item.id) } } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(item.isCompleted ? ItemKind.todo.color : Theme.dim)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).foregroundStyle(Theme.text)
                if let due = item.dueDate {
                    Text(due.shortRelative(includeTime: item.dueHasTime)).font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { app.detailItemID = item.id }
    }
}

struct CategoryEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let original: ItemCategory?
    @State private var name: String
    @State private var emoji: String
    @State private var colorHex: String
    @State private var confirmDelete = false

    init(category: ItemCategory?) {
        original = category
        _name = State(initialValue: category?.name ?? "")
        _emoji = State(initialValue: category?.emoji ?? CategoryPalette.defaultEmoji)
        _colorHex = State(initialValue: category?.colorHex ?? CategoryPalette.colors[0])
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
            }
            Section("Emoji") {
                TextField("Emoji", text: $emoji)
                    .font(.largeTitle)
                    .onChange(of: emoji) { _, new in
                        if new.count > 1, let last = new.last { emoji = String(last) }
                    }
            }
            Section("Colour") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(CategoryPalette.colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
                            .overlay { if hex == colorHex { Circle().stroke(.white, lineWidth: 3).padding(-4) } }
                            .onTapGesture { colorHex = hex }
                    }
                }
                .padding(.vertical, 6)
            }
            if let original {
                Section {
                    Button("Delete category", role: .destructive) { confirmDelete = true }
                }
                .confirmationDialog("Delete \(original.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        library.deleteCategory(original.id)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(original == nil ? "New category" : "Edit category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let finalEmoji = emoji.isEmpty ? CategoryPalette.defaultEmoji : emoji
                    if var category = original {
                        category.name = trimmed
                        category.emoji = finalEmoji
                        category.colorHex = colorHex
                        library.updateCategory(category)
                    } else {
                        library.createCategory(name: trimmed, emoji: finalEmoji, colorHex: colorHex)
                    }
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
