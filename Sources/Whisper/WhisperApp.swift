import SwiftUI

@main
struct WhisperApp: App {
    @StateObject private var coordinator = Coordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(coordinator: coordinator)
        } label: {
            MenuBarLabel(state: coordinator.state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(coordinator: coordinator)
                .frame(width: 800, height: 560)
                .floatingWindow()   // keep Settings above other apps
        }
    }
}
