import SwiftUI
import ThoughtCloudKit

struct CloudScreen: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    @State private var cloud = CloudModel()
    @State private var lastMagnification: CGFloat = 1
    @State private var path = NavigationPath()
    @AppStorage("cloud.showCompleted") private var showCompleted = true
    @AppStorage("cloud.hiddenKinds") private var hiddenKindsRaw = ""

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ZStack {
                    canvas
                    overlays
                }
                .onAppear {
                    cloud.setViewSize(GraphPoint(geo.size))
                    rebuild()
                }
                .onChange(of: geo.size) { _, size in cloud.setViewSize(GraphPoint(size)) }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { CategoryScreen(categoryID: $0) }
        }
        .onChange(of: library.snapshot) { rebuild() }
        .onChange(of: showCompleted) { rebuild() }
        .onChange(of: hiddenKindsRaw) { rebuild() }
        // Restarts the moment animation is needed, so there is no polling delay.
        .task(id: cloud.needsAnimation) {
            while cloud.needsAnimation && !Task.isCancelled {
                cloud.tick()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    // MARK: - Canvas

    private var hasDue: Bool { cloud.graph.nodes.contains { $0.isDue } }

    private var canvas: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !hasDue)) { timeline in
            let _ = cloud.frame
            let frame = CloudRenderer.Frame(
                graph: cloud.graph,
                positions: cloud.layout.positions,
                camera: cloud.camera,
                viewSize: cloud.viewSize,
                selection: cloud.selection,
                highlighted: cloud.highlighted,
                time: timeline.date.timeIntervalSinceReferenceDate
            )
            Canvas { ctx, _ in CloudRenderer.draw(&ctx, frame) }
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in
            withAnimation(.snappy) { cloud.tap(at: GraphPoint(value.location)) }
        })
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { cloud.dragChanged(start: GraphPoint($0.startLocation), location: GraphPoint($0.location)) }
                .onEnded { _ in cloud.dragEnded() }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    cloud.pinch(by: value.magnification / lastMagnification, anchor: GraphPoint(value.startLocation))
                    lastMagnification = value.magnification
                }
                .onEnded { _ in lastMagnification = 1 }
        )
    }

    private func rebuild() {
        let hidden = Set(hiddenKindsRaw.split(separator: ",").compactMap { ItemKind(rawValue: String($0)) })
        let options = GraphOptions(showCompleted: showCompleted, kinds: Set(ItemKind.allCases).subtracting(hidden))
        cloud.update(graph: GraphBuilder.build(from: library, options: options))
    }

    // MARK: - Overlays

    private var overlays: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            if library.items.isEmpty {
                EmptyStateView(symbol: "circle.hexagongrid", title: "Your cloud is empty")
                Spacer()
            }
            if cloud.selection == nil {
                footer
            }
        }
        .overlay(alignment: .bottom) {
            if let node = cloud.selectedNode {
                NodeSheet(node: node, cloud: cloud, openCategory: { path.append($0) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(node.id)
            }
        }
        .animation(.snappy(duration: 0.25), value: cloud.selection)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud").font(.largeTitle.weight(.bold)).shadow(color: .black, radius: 8)
                Text(summary).font(.footnote).foregroundStyle(Theme.dim)
            }
            Spacer()
            filterMenu
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var summary: String {
        let items = library.items.filter { !$0.isArchived }
        let due = library.dueReviews().count
        return "\(items.count) items · \(library.links.count) links" + (due > 0 ? " · \(due) due" : "")
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Show completed todos", isOn: $showCompleted)
            Section("Show") {
                ForEach(ItemKind.allCases) { kind in
                    Toggle(kind.plural, systemImage: kind.symbol, isOn: Binding(
                        get: { !hiddenKindsRaw.split(separator: ",").contains(Substring(kind.rawValue)) },
                        set: { visible in
                            var hidden = Set(hiddenKindsRaw.split(separator: ",").map(String.init))
                            if visible { hidden.remove(kind.rawValue) } else { hidden.insert(kind.rawValue) }
                            hiddenKindsRaw = hidden.sorted().joined(separator: ",")
                        }
                    ))
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease").frame(width: 36, height: 36).background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 10) {
                legend(Circle(), "thought")
                legend(RoundedRectangle(cornerRadius: 1.5), "todo")
                legend(Rectangle().rotation(.degrees(45)).scale(0.8), "review")
                legend(EventHexagon(), "event")
            }
            .font(.caption2)
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            Spacer()
            VStack(spacing: 0) {
                zoomButton("plus") { cloud.zoom(by: 1.4) }
                Divider().frame(width: 44)
                zoomButton("minus") { cloud.zoom(by: 1 / 1.4) }
                Divider().frame(width: 44)
                zoomButton("arrow.up.left.and.arrow.down.right") { cloud.fit(animated: false) }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func legend<S: Shape>(_ shape: S, _ label: String) -> some View {
        HStack(spacing: 4) {
            shape.fill(Theme.dim).frame(width: 7, height: 7)
            Text(label)
        }
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }
}

private struct EventHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        CloudRenderer.shapePath(.event, CGPoint(x: rect.midX, y: rect.midY), min(rect.width, rect.height) / 2.2)
    }
}
