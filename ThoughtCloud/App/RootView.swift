import SwiftUI
import ThoughtCloudKit

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            Group {
                switch app.tab {
                case .cloud: CloudScreen()
                case .todos: TodosScreen()
                case .events: EventsScreen()
                case .thoughts: ThoughtsScreen()
                case .review: ReviewScreen()
                case .settings: SettingsScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar()
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(item: $app.capture) { request in
            CaptureSheet(request: request)
        }
        .sheet(item: Binding(
            get: { app.detailItemID.map(IdentifiedID.init) },
            set: { app.detailItemID = $0?.id }
        )) { wrapper in
            ItemDetailSheet(itemID: wrapper.id)
        }
        .overlay(alignment: .top) {
            if let error = library.lastError {
                Text(error)
                    .font(.footnote)
                    .padding(10)
                    .background(Theme.danger.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                    .padding()
                    .onTapGesture { library.lastError = nil }
            }
        }
    }
}

struct IdentifiedID: Identifiable {
    let id: UUID
}

struct TabBar: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library

    var body: some View {
        let dueCount = library.dueReviews().count
        HStack(alignment: .top) {
            tab(.cloud, "Cloud", "circle.hexagongrid", Theme.accent)
            tab(.todos, "Todos", "checkmark.circle", ItemKind.todo.color)
            tab(.events, "Events", "calendar", ItemKind.event.color, fills: false)
            captureButton
            tab(.thoughts, "Thoughts", "lightbulb", ItemKind.thought.color)
            tab(.review, "Review", "rectangle.stack", ItemKind.review.color, badge: dueCount)
            tab(.settings, "Settings", "gearshape", Theme.text)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var captureButton: some View {
        Button {
            app.presentCapture(kind: app.captureKindForCurrentTab)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Theme.captureGradient, in: Circle())
                .shadow(color: ItemKind.review.color.opacity(0.45), radius: 12, y: 4)
        }
        .offset(y: -18)
        .frame(maxWidth: .infinity)
        .contextMenu {
            ForEach(ItemKind.allCases) { kind in
                Button("New \(kind.label)", systemImage: kind.symbol) { app.presentCapture(kind: kind) }
            }
        }
        .accessibilityLabel("Capture")
    }

    private func tab(_ tab: AppTab, _ title: String, _ symbol: String, _ color: Color, badge: Int = 0, fills: Bool = true) -> some View {
        let selected = app.tab == tab
        return Button {
            app.tab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected && fills ? symbol + ".fill" : symbol)
                    .font(.system(size: 20))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(color, in: Capsule())
                                .foregroundStyle(.black)
                                .offset(x: 10, y: -6)
                        }
                    }
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selected ? color : Theme.dim)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
