import EventKit
import SwiftUI
import ThoughtCloudKit

struct SettingsScreen: View {
    @Environment(Library.self) private var library
    @Environment(AppState.self) private var app
    @State private var editing: ItemCategory?
    @State private var creating = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section("Categories") {
                    ForEach(library.categories) { category in
                        Button { editing = category } label: {
                            HStack {
                                Text(category.emoji)
                                Text(category.name).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(library.items(inCategory: category.id).count)").foregroundStyle(Theme.dim)
                                Circle().fill(Color(hex: category.colorHex)).frame(width: 12, height: 12)
                            }
                        }
                    }
                    Button("New category", systemImage: "plus") { creating = true }
                }

                Section("Calendar") {
                    LabeledContent("Access", value: calendarStatusText)
                    if calendarStatus == .notDetermined {
                        Button("Allow calendar access") { app.calendarSync?.requestAccessIfNeeded() }
                    } else if calendarStatus != .fullAccess {
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }

                Section("Data") {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Export JSON", systemImage: "square.and.arrow.up") }
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .onAppear { app.calendarSync?.refreshStatus() }
            .sheet(item: $editing) { category in
                NavigationStack { CategoryEditor(category: category) }
            }
            .sheet(isPresented: $creating) {
                NavigationStack { CategoryEditor(category: nil) }
            }
            .onAppear(perform: prepareExport)
        }
    }

    private var calendarStatus: EKAuthorizationStatus {
        app.calendarSync?.status ?? EKEventStore.authorizationStatus(for: .event)
    }

    private var calendarStatusText: String {
        switch calendarStatus {
        case .fullAccess: "On"
        case .notDetermined: "Not asked"
        case .writeOnly: "Add only"
        default: "Off"
        }
    }

    private func prepareExport() {
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ThoughtCloud-\(stamp).json")
        do {
            try library.exportData().write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}
