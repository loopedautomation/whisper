import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject private var state: AppState
    @Environment(\.openSettings) private var openSettings

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        self.state = coordinator.state
    }

    var body: some View {
        Text(state.status.menuLabel)

        if let warning = state.lastWarning {
            Text("⚠︎ \(warning)")
        }

        Divider()

        Button(state.isRecording ? "Stop Recording" : "Start Recording") {
            coordinator.toggleRecording()
        }

        if !state.lastTranscript.isEmpty {
            Button("Copy Last Transcript") {
                ClipboardService.set(state.lastTranscript)
            }
        }

        Divider()

        Text("Model: \(WhisperModel.label(for: selectedModel))")

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

        Button("About Looped Whisper") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }

        Divider()

        Button("Quit Looped Whisper") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var selectedModel: String {
        UserDefaults.standard.string(forKey: PrefKey.selectedModel) ?? "base"
    }
}
