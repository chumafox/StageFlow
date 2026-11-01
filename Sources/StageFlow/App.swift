import SwiftUI

@main
struct StageFlowApp: App {
    var body: some Scene {
        WindowGroup {
            StageFlowMainView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1040, height: 680)
    }
}
