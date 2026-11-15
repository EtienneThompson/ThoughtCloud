import SwiftUI
import ThoughtCloudKit

/// Everything about one item: edit text, kind, categories, dates, links.
struct ItemDetailSheet: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID

    @State private var title = ""
    @State private var bodyText = ""
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var newCategoryName = ""
    @State private var showNewCategory = false
    @State private var newSubtask = ""
    @FocusState private var newSubtaskFocused: Bool

    var body: some View {
        NavigationStack {
            if let item = library.item(itemID) {
                form(item)
                    .navigationTitle(item.kind.label)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { commitText(); dismiss() }
                        }
                    }
                    .onAppear {
                        guard !loaded else { return }
                        title = item.title
                        bodyText = item.body
                        loaded = true
                    }
                    .onDisappear { commitText() }
            } else {
                EmptyStateView(symbol: "questionmark", title: "Item not found")
            }
        }
        .presentationDetents([.large])
    }

    private func commitText() {
        guard loaded, let item = library.item(itemID) else { return }
        if item.title != title || item.body != bodyText {
            library.updateText(itemID, title: title, body: bodyText)
        }
    }

    // MARK: - Form

    private func form(_ item: Item) -> some View {
        Form {
            Section {
                TextField("Title", text: $title, axis: .vertical).font(.headline)
                TextField("Details", text: $bodyText, axis: .vertical)
                    .lineLimit(3...14)
            }

            Section {
                Picker("Kind", selection: Binding(get: { item.kind }, set: { commitText(); library.setKind(itemID, $0) })) {
                    ForEach(ItemKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            categoriesSection(item)

            switch item.kind {
            case .todo:
                todoSection(item)
                subtasksSection(item)
            case .review: reviewSection(item)
            case .thought: thoughtSection(item)
            case .event: eventSections(item)
            }

            linksSection(item)

            Section {
                if item.isArchived {
                    Button("Restore from archive", systemImage: "arrow.uturn.backward") { library.setArchived(itemID, false) }
                } else {
                    Button("Archive", systemImage: "archivebox") { library.setArchived(itemID, true); dismiss() }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · edited \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(hex: "#141419"))
        .confirmationDialog("Delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { library.delete(itemID); dismiss() }
        }
        .alert("New category", isPresented: $showNewCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Add") {
                let category = library.createCategory(name: newCategoryName)
                if let current = library.item(itemID), !current.categoryIDs.contains(category.id) {
                    library.setCategories(itemID, current.categoryIDs + [category.id])
                }
                newCategoryName = ""
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
    }

    private func categoriesSection(_ item: Item) -> some View {
        Section("Categories") {
            FlowLayout {
                ForEach(library.categories) { category in
                    let on = item.categoryIDs.contains(category.id)
                    Chip(title: "\(category.emoji) \(category.name)", color: Color(hex: category.colorHex), isOn: on) {
                        var ids = item.categoryIDs
                        if on { ids.removeAll { $0 == category.id } } else { ids.append(category.id) }
                        library.setCategories(itemID, ids)
                    }
                }
                Chip(title: "＋ New", dashed: true) { showNewCategory = true }
            }
            .padding(.vertical, 4)
        }
    }

    private func todoSection(_ item: Item) -> some View {
        Section("Todo") {
            Toggle("Done", isOn: Binding(get: { item.isCompleted }, set: { _ in library.toggleCompleted(itemID) }))
            Toggle("Due date", isOn: Binding(
                get: { item.dueDate != nil },
                set: { on in library.setDueDate(itemID, on ? Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)) : nil, hasTime: false) }
            ))
            if let due = item.dueDate {
                Toggle("Include time", isOn: Binding(get: { item.dueHasTime }, set: { library.setDueDate(itemID, due, hasTime: $0) }))
                DatePicker("Due", selection: Binding(get: { due }, set: { library.setDueDate(itemID, $0, hasTime: item.dueHasTime) }),
                           displayedComponents: item.dueHasTime ? [.date, .hourAndMinute] : [.date])
            }
        }
    }

    private func subtasksSection(_ item: Item) -> some View {
        let progress = item.subtaskProgress
        return Section {
            ForEach(item.subtasks) { subtask in
                SubtaskRow(itemID: itemID, subtask: subtask)
            }
            .onDelete { offsets in
                for index in offsets { library.deleteSubtask(itemID, item.subtasks[index].id) }
            }
            .onMove { library.moveSubtasks(itemID, from: $0, to: $1) }
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").font(.system(size: 20)).foregroundStyle(Theme.dim)
                TextField("Add subtask", text: $newSubtask)
                    .focused($newSubtaskFocused)
                    .submitLabel(.next)
                    .onSubmit {
                        library.addSubtask(to: itemID, title: newSubtask)
                        newSubtask = ""
                        newSubtaskFocused = true
                    }
            }
        } header: {
            HStack {
                Text("Subtasks")
                Spacer()
                if progress.total > 0 { Text("\(progress.done)/\(progress.total)") }
            }
        }
    }

    @ViewBuilder
    private func eventSections(_ item: Item) -> some View {
        if let event = item.event {
            let components: DatePickerComponents = event.isAllDay ? [.date] : [.date, .hourAndMinute]
            Section("When") {
                Toggle("All day", isOn: Binding(
                    get: { event.isAllDay },
                    set: { allDay in
                        let start = allDay ? event.start : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: event.start) ?? event.start
                        library.setEventTimes(itemID, start: start, end: allDay ? event.end : start.addingTimeInterval(3600), isAllDay: allDay)
                    }
                ))
                DatePicker("Starts", selection: Binding(
                    get: { event.start },
                    set: { start in
                        // Keep the duration when the start moves.
                        let duration = event.end.timeIntervalSince(event.start)
                        library.setEventTimes(itemID, start: start, end: start.addingTimeInterval(duration), isAllDay: event.isAllDay)
                    }
                ), displayedComponents: components)
                DatePicker("Ends", selection: Binding(
                    get: { event.end },
                    set: { library.setEventTimes(itemID, start: event.start, end: $0, isAllDay: event.isAllDay) }
                ), in: event.start..., displayedComponents: components)
            }
            Section {
                Toggle("In Calendar", isOn: Binding(get: { event.addToCalendar }, set: { library.setAddToCalendar(itemID, $0) }))
            }
            if let state = item.review {
                Section("Review") {
                    LabeledContent("Next", value: state.nextReviewAt <= Date() ? "Now" : state.nextReviewAt.shortRelative(includeTime: false))
                    LabeledContent("Seen", value: "\(state.seenCount)×")
                    Button("Review again soon") { library.grade(itemID, .again) }
                }
            }
        }
    }

    private func reviewSection(_ item: Item) -> some View {
        Section {
            Toggle("Remember until", isOn: Binding(
                get: { item.review?.rememberUntil != nil },
                set: { on in library.setRememberUntil(itemID, on ? Calendar.current.date(byAdding: .day, value: 7, to: Date()) : nil) }
            ))
            if let until = item.review?.rememberUntil {
                DatePicker("Until", selection: Binding(get: { until }, set: { library.setRememberUntil(itemID, $0) }), displayedComponents: [.date])
            }
            if let state = item.review {
                LabeledContent("Next review", value: state.nextReviewAt <= Date() ? "Now" : state.nextReviewAt.shortRelative(includeTime: false))
                LabeledContent("Seen", value: "\(state.seenCount)×")
                Button("Review again soon") { library.grade(itemID, .again) }
            }
        } header: {
            Text("Review")
        }
    }

    private func thoughtSection(_ item: Item) -> some View {
        Section {
            Button("Turn into a Todo", systemImage: ItemKind.todo.symbol) {
                commitText()
                if let new = library.promote(itemID, to: .todo) { app.detailItemID = new.id }
            }
            Button("Turn into a Review card", systemImage: ItemKind.review.symbol) {
                commitText()
                if let new = library.promote(itemID, to: .review) { app.detailItemID = new.id }
            }
        }
    }

    private func linksSection(_ item: Item) -> some View {
        Section("Linked") {
            ForEach(library.linkedItems(of: itemID)) { other in
                Button {
                    commitText()
                    app.detailItemID = other.id
                } label: {
                    Label(other.displayTitle, systemImage: other.kind.symbol)
                        .foregroundStyle(Theme.text)
                }
                .swipeActions {
                    Button("Unlink", role: .destructive) { library.unlink(itemID, other.id) }
                }
            }
            NavigationLink {
                LinkPicker(itemID: itemID)
            } label: {
                Label("Link to…", systemImage: "link")
            }
        }
    }
}

struct SubtaskRow: View {
    @Environment(Library.self) private var library
    let itemID: UUID
    let subtask: Subtask
    @State private var title = ""

    var body: some View {
        HStack(spacing: 10) {
            Button { library.toggleSubtask(itemID, subtask.id) } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(subtask.isCompleted ? ItemKind.todo.color : Theme.dim)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            TextField("Subtask", text: $title, axis: .vertical)
                .strikethrough(subtask.isCompleted)
                .foregroundStyle(subtask.isCompleted ? Theme.dim : Theme.text)
                .onSubmit(commit)
        }
        .onAppear { title = subtask.title }
        .onChange(of: subtask.title) { _, new in title = new }
        .onDisappear(perform: commit)
        .onChange(of: title) { _, new in
            // Vertical text fields insert a newline on return; treat it as done editing.
            if new.contains("\n") { title = new.replacingOccurrences(of: "\n", with: ""); commit() }
        }
    }

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            title = subtask.title
        } else if trimmed != subtask.title {
            library.renameSubtask(itemID, subtask.id, title: trimmed)
        }
    }
}

struct LinkPicker: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID
    @State private var search = ""

    var body: some View {
        let linked = Set(library.linkedItems(of: itemID).map(\.id))
        List(candidates.filter { !linked.contains($0.id) }) { item in
            Button {
                library.link(itemID, item.id)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: item.kind.symbol).foregroundStyle(item.kind.color)
                    VStack(alignment: .leading) {
                        Text(item.displayTitle).foregroundStyle(Theme.text)
                        CategoryPills(style: library.style(for: item), compact: true)
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Link to")
    }

    private var candidates: [Item] {
        library.items
            .filter { $0.id != itemID && !$0.isArchived }
            .filter { search.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(search) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
