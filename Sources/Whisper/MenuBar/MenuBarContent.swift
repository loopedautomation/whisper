import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject private var state: AppState
    @ObservedObject private var audioDevices: AudioDeviceManager
    @ObservedObject private var models: ModelManager
    @ObservedObject private var updates: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        self.state = coordinator.state
        self.audioDevices = coordinator.audioDevices
        self.models = coordinator.models
        self.updates = coordinator.updateChecker
    }

    var body: some View {
        Text(appName)
        Divider()

        Text(state.status.menuLabel)

        if let error = state.lastError {
            Text("⛔︎ \(error.displayText)")
            Button("Dismiss") { state.clearError() }
        }

        if let warning = state.lastWarning {
            Text("⚠︎ \(warning)")
        }

        Divider()

        Button(state.isRecording ? "Stop Recording" : "Start Recording") {
            coordinator.toggleRecording()
        }

        Picker("Microphone", selection: $audioDevices.selectedUID) {
            Text("System Default").tag(AudioInputDevices.systemDefaultUID)
            if !audioDevices.devices.isEmpty {
                Divider()
                ForEach(audioDevices.devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
        }

        if !state.lastTranscript.isEmpty {
            Button("Copy Last Transcript") {
                ClipboardService.set(state.lastTranscript)
            }
        }

        Divider()

        let installed = WhisperModel.known.filter { models.isDownloaded($0.id) }
        if installed.isEmpty {
            Text("No models installed — download in Settings")
        } else {
            Picker("Model", selection: modelBinding) {
                ForEach(installed) { Text($0.label).tag($0.id) }
            }
        }

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

        if case .updateAvailable(let version, _) = updates.state {
            Button("⬆︎ Update Available (\(version))") {
                updates.openDownloadPage()
            }
        }

        Button("Check for Updates…") {
            coordinator.checkForUpdates()
        }

        Divider()

        Button("Quit Looped Whisper") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Looped Whisper"
    }

    private var selectedModel: String {
        UserDefaults.standard.string(forKey: PrefKey.selectedModel) ?? "base"
    }

    /// Switches the active model and loads it (only installed models are listed,
    /// so this never triggers a download).
    private var modelBinding: Binding<String> {
        Binding(
            get: { selectedModel },
            set: { newID in
                guard newID != selectedModel else { return }
                UserDefaults.standard.set(newID, forKey: PrefKey.selectedModel)
                Task { await coordinator.loadModel(newID) }
            }
        )
    }
}
