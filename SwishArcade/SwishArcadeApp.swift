import SwiftUI

/// SWISH ARCADE — the native rebuild ("the ad made real").
/// No web core, no embedded browser: the whole game is SwiftUI.
@main
struct SwishArcadeApp: App {
    @StateObject private var viewModel = GameViewModel()

    var body: some Scene {
        WindowGroup {
            GameScreen()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
