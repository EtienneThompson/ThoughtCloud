import SwiftUI
import ThoughtCloudKit

/// One field, zero forms. Type, optionally tap a category, save.
struct CaptureSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: CaptureModel
    @State private var savedCount = 0
    @FocusState private var focused: Bool

    init(request: CaptureRequest) {
        let app = AppState.shared
        _model = State(initialValue: CaptureModel(library: app.library, parser: app.parser, presetCategoryIDs: request.categoryIDs, presetKind: request.kind))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            kindPicker
            TextField("What's on your mind?", text: $model.text, axis: .vertical)
                .font(.title3)
                .lineLimit(1...6) // scrolls inside once it's longer
                .focused($focused)
                .textInputAutocapitalization(.sentences)
            dateRow
            categoryRow
                .layoutPriority(1)
            Spacer(minLength: 0)
            saveRow
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background(Color(hex: "#1C1C24"))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(hex: "#1C1C24"))
        .onAppear { focused = true }
        .sensoryFeedback(.success, trigger: savedCount)
    }

    // MARK: - Pieces

    private var kindPicker: some View {
        HStack(spacing: 4) {
            ForEach(ItemKind.allCases) { kind in
                let on = model.kind == kind
                Button {
                    model.chooseKind(kind)
                } label: {
                    Label(kind.label, systemImage: kind.symbol)
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(on ? kind.color : Theme.dim)
                        .background(on ? kind.color.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12))
        .animation(.snappy(duration: 0.2), value: model.kind)
    }

    @ViewBuilder
    private var dateRow: some View {
        if let event = model.eventPreview {
            HStack(spacing: 6) {
                chip("📅 " + event.whenText, color: ItemKind.event.color, dismissible: model.detectedDate != nil) { model.dismissDate() }
                chip(model.addToCalendar ? "Calendar ✓" : "Calendar", color: model.addToCalendar ? Theme.text : Theme.dim, symbol: "calendar") {
                    model.addToCalendar.toggle()
                }
            }
        } else if let date = model.detectedDate {
            let prefix = model.kind == .review ? "Until " : "📅 "
            chip(prefix + date.date.shortRelative(includeTime: date.hasTime), color: model.kind.color, dismissible: true) { model.dismissDate() }
        }
    }

    private func chip(_ title: String, color: Color, symbol: String? = nil, dismissible: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
                if dismissible { Image(systemName: "xmark").font(.caption2) }
            }
            .font(.caption)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var categoryRow: some View {
        let selected = model.selectedCategoryIDs
        FlowLayout(spacing: 6) {
            if model.draft.hashtagInProgress != nil {
                ForEach(model.autocomplete) { category in
                    Chip(title: "\(category.emoji) \(category.name)", color: Color(hex: category.colorHex)) {
                        model.complete(with: category)
                    }
                }
            } else {
                ForEach(model.orderedCategories) { category in
                    Chip(title: "\(category.emoji) \(category.name)", color: Color(hex: category.colorHex), isOn: selected.contains(category.id)) {
                        model.toggleCategory(category.id)
                    }
                }
                ForEach(model.newCategoryNames, id: \.self) { name in
                    Chip(title: "＋ \(name)", color: Theme.text, isOn: true, dashed: true) {}
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveRow: some View {
        HStack {
            if savedCount > 0 {
                Label("\(savedCount) saved", systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(Theme.success)
                    .transition(.opacity)
            }
            Spacer()
            Button {
                if model.save() != nil { savedCount += 1 }
                focused = true
            } label: {
                Label("Next", systemImage: "arrow.uturn.down")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canSave)

            Button {
                if model.save() != nil { savedCount += 1 }
                dismiss()
            } label: {
                Text("Save").font(.headline).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.kind.color)
            .disabled(!model.canSave)
        }
    }
}
