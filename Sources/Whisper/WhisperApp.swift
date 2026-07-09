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
                .frame(width: 620, height: 420)
                .floatingWindow()   // keep Settings above other apps
        }
    }
}
