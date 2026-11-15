import SwiftUI
import ThoughtCloudKit

@main
struct ThoughtCloudApp: App {
    @State private var app = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.library)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.calendarSync?.refreshStatus()
                app.library.refresh()
                app.library.syncPendingCalendarEvents()
            }
        }
    }
}
