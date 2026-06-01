import SwiftUI

/// App entry. Builds the DI container once, injects it into the view tree, and forwards scene-phase
/// transitions so the live poll loop runs only while foregrounded (see PORTING_NOTES.md §1 — iOS
/// has no foreground-service equivalent).
@main
struct PiSkyApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .preferredColorScheme(.dark)
                .tint(Palette.brass)
                .task { await container.bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            container.handleScenePhase(phase)
        }
    }
}
