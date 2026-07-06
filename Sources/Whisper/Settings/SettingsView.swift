import SwiftUI
import KeyboardShortcuts

private let d = UserDefaults.standard

struct SettingsView: View {
    @ObservedObject var coordinator: Coordinator

    var body: some View {
        TabView {
            GeneralTab(coordinator: coordinator)
                .tabItem { Label("General", systemImage: "gear") }
            ModelTab(coordinator: coordinator)
                .tabItem { Label("Model", systemImage: "waveform") }
            HotkeysTab(coordinator: coordinator)
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            SoundsTab()
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            VocabularyTab(vocabulary: coordinator.vocabulary)
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            RewriteTab()
                .tabItem { Label("Rewrite", systemImage: "wand.and.stars") }
            PermissionsTab(permissions: coordinator.permissions)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
    }
}

// MARK: - Reusable Save button with Saving… / Saved states

enum SaveState { case idle, saving, saved }

struct SaveButton: View {
    var disabled: Bool = false
    let action: () -> Void
    @State private var state: SaveState = .idle

    var body: some View {
        Button(action: trigger) {
            Group {
                switch state {
                case .idle:
                    Text("Save")
                case .saving:
                    HStack(spacing: 5) { ProgressView().controlSize(.small); Text("Saving…") }
                case .saved:
                    Label("Saved", systemImage: "checkmark")
                }
            }
            .frame(width: 90)
        }
        .controlSize(.large)
        .keyboardShortcut("s", modifiers: .command)
        .disabled(disabled || state != .idle)
    }

    private func trigger() {
        state = .saving
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { state = .saved }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation { state = .idle }
            }
        }
    }
}

/// A page footer that right-aligns the Save button below a Divider.
private struct SaveBar: View {
    var disabled: Bool
    let action: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack { Spacer(); SaveButton(disabled: disabled, action: action) }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject private var loginItem: LoginItemManager

    @State private var mode = d.string(forKey: PrefKey.transcriptionMode) ?? TranscriptionMode.batch.rawValue
    @State private var realtimeInsertion = d.string(forKey: PrefKey.realtimeInsertion) ?? RealtimeInsertion.onStop.rawValue
    @State private var outputBehavior = d.string(forKey: PrefKey.outputBehavior) ?? OutputBehavior.copyPaste.rawValue
    @State private var restoreClipboard = d.bool(forKey: PrefKey.restoreClipboard)

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        self.loginItem = coordinator.loginItem
    }

    private var isDirty: Bool {
        mode != d.string(forKey: PrefKey.transcriptionMode)
        || realtimeInsertion != d.string(forKey: PrefKey.realtimeInsertion)
        || outputBehavior != d.string(forKey: PrefKey.outputBehavior)
        || restoreClipboard != d.bool(forKey: PrefKey.restoreClipboard)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                Text(loginItem.requiresApproval
                     ? "Enable Looped Whisper in System Settings → General → Login Items." : " ")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)

                Picker("Transcription mode", selection: $mode) {
                    ForEach(TranscriptionMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Realtime insertion", selection: $realtimeInsertion) {
                    ForEach(RealtimeInsertion.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .disabled(mode != TranscriptionMode.realtime.rawValue)

                Picker("Output", selection: $outputBehavior) {
                    ForEach(OutputBehavior.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Restore previous clipboard after paste", isOn: $restoreClipboard)
                    .disabled(outputBehavior != OutputBehavior.copyPaste.rawValue)
            }
            Spacer()
            SaveBar(disabled: !isDirty) {
                d.set(mode, forKey: PrefKey.transcriptionMode)
                d.set(realtimeInsertion, forKey: PrefKey.realtimeInsertion)
                d.set(outputBehavior, forKey: PrefKey.outputBehavior)
                d.set(restoreClipboard, forKey: PrefKey.restoreClipboard)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { loginItem.refresh() }
    }
}

// MARK: - Model

private struct ModelTab: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject private var models: ModelManager
    @State private var selectedModel = d.string(forKey: PrefKey.selectedModel) ?? "base"
    @State private var languages = WhisperLanguage.codes(from: d.string(forKey: PrefKey.preferredLanguages) ?? "en")

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        self.models = coordinator.models
    }

    private var storedLanguages: Set<String> {
        WhisperLanguage.codes(from: d.string(forKey: PrefKey.preferredLanguages) ?? "en")
    }

    private var isDirty: Bool {
        selectedModel != d.string(forKey: PrefKey.selectedModel)
        || languages != storedLanguages
    }

    private func toggle(_ code: String) {
        if languages.contains(code) { languages.remove(code) } else { languages.insert(code) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active model").frame(width: 110, alignment: .leading)
                Picker("", selection: $selectedModel) {
                    ForEach(WhisperModel.known) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
            }
            HStack(alignment: .top) {
                Text("Language").frame(width: 110, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        // Multi-select: check every language you speak. The menu
                        // stays open so you can pick several in one pass.
                        ForEach(WhisperLanguage.known.filter { !$0.code.isEmpty }) { lang in
                            Toggle(isOn: Binding(
                                get: { languages.contains(lang.code) },
                                set: { _ in toggle(lang.code) }
                            )) { Text(lang.label) }
                        }
                    } label: {
                        Text(WhisperLanguage.summary(for: languages))
                    }
                    .frame(maxWidth: 220)

                    Text(languages.count == 1
                         ? "Pinned — everything is transcribed as this language."
                         : "Auto-detects the language of each recording.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "folder")
                Text(models.baseURL.path)
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    .help(models.baseURL.path)
                Spacer()
                Button("Reveal") { models.revealBaseInFinder() }
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(WhisperModel.known) { model in
                        ModelRow(model: model, manager: models, activeModelID: selectedModel)
                        Divider()
                    }
                }
                // Reserve space on the trailing edge so per-row buttons (e.g. Reveal
                // in Finder) aren't hidden behind the macOS overlay scroller.
                .padding(.trailing, 12)
            }
            .frame(maxHeight: .infinity)

            SaveBar(disabled: !isDirty) {
                d.set(WhisperLanguage.string(from: languages), forKey: PrefKey.preferredLanguages)
                if selectedModel != d.string(forKey: PrefKey.selectedModel) {
                    d.set(selectedModel, forKey: PrefKey.selectedModel)
                    Task { await coordinator.loadModel(selectedModel) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { models.refreshAll() }
    }
}

private struct ModelRow: View {
    let model: WhisperModel
    @ObservedObject var manager: ModelManager
    /// The currently selected/active model; deleting it would break transcription,
    /// so the Delete affordance is disabled for it.
    var activeModelID: String
    @State private var confirmingDelete = false

    private var isActive: Bool { model.id == activeModelID }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.label).fontWeight(.medium)
                Text(model.note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            trailing.frame(width: 180, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .confirmationDialog(
            "Delete the \(model.label) model?",
            isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { manager.delete(model.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the downloaded files from disk. You can download it again at any time.")
        }
    }

    @ViewBuilder private var trailing: some View {
        switch manager.state(for: model.id) {
        case .downloaded:
            HStack(spacing: 6) {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly).foregroundStyle(BrandColor.success)
                Button { manager.revealInFinder(model.id) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Reveal in Finder")
                Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(isActive)
                    .help(isActive ? "Can’t delete the active model" : "Delete from disk")
            }
        case .notDownloaded:
            Button("Download") { manager.startDownload(model.id) }
        case .downloading(let fraction):
            HStack(spacing: 6) {
                ProgressView(value: fraction).frame(width: 60)
                Text("\(Int(fraction * 100))%").font(.caption.monospacedDigit())
                Button { manager.cancelDownload(model.id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).help("Cancel download")
            }
        case .failed(let message):
            Button("Retry") { manager.startDownload(model.id) }.help(message)
        }
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    @ObservedObject var coordinator: Coordinator
    @State private var fnEnabled = d.bool(forKey: PrefKey.fnEnabled)
    @State private var fnMode = d.string(forKey: PrefKey.fnMode) ?? FnMode.holdPTT.rawValue

    private var isDirty: Bool {
        fnEnabled != d.bool(forKey: PrefKey.fnEnabled) || fnMode != d.string(forKey: PrefKey.fnMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                KeyboardShortcuts.Recorder("Push to talk (hold):", name: .pushToTalk)
                KeyboardShortcuts.Recorder("Toggle recording:", name: .toggleRecording)
                Toggle("Use the fn / Globe key", isOn: $fnEnabled)
                Picker("fn action", selection: $fnMode) {
                    ForEach(FnMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .disabled(!fnEnabled)
            }

            Text("Standard shortcuts save automatically. macOS uses double-tap fn for Dictation — set System Settings → Keyboard → “Press 🌐 to” → Do Nothing to avoid conflicts. The fn key may not work on non-Apple keyboards, so keep a standard shortcut as a fallback.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Keyboard Settings") { coordinator.permissions.openKeyboardSettings() }
                .disabled(!fnEnabled)

            Spacer()
            SaveBar(disabled: !isDirty) {
                d.set(fnEnabled, forKey: PrefKey.fnEnabled)
                d.set(fnMode, forKey: PrefKey.fnMode)
                coordinator.configureFnMonitor()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Sounds

private struct SoundsTab: View {
    @State private var enabled = d.bool(forKey: PrefKey.soundsEnabled)
    @State private var volume = d.double(forKey: PrefKey.soundVolume)
    @State private var perEvent: [String: (on: Bool, name: String)] = [:]

    private func load() {
        enabled = d.bool(forKey: PrefKey.soundsEnabled)
        volume = d.double(forKey: PrefKey.soundVolume)
        var map: [String: (Bool, String)] = [:]
        for e in SoundEvent.allCases {
            map[e.rawValue] = (d.bool(forKey: e.enabledKey), d.string(forKey: e.nameKey) ?? e.defaultSound)
        }
        perEvent = map
    }

    private var isDirty: Bool {
        if enabled != d.bool(forKey: PrefKey.soundsEnabled) { return true }
        if volume != d.double(forKey: PrefKey.soundVolume) { return true }
        for e in SoundEvent.allCases {
            guard let v = perEvent[e.rawValue] else { continue }
            if v.on != d.bool(forKey: e.enabledKey) { return true }
            if v.name != (d.string(forKey: e.nameKey) ?? e.defaultSound) { return true }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Play sound effects", isOn: $enabled)

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $volume, in: 0...1) { editing in
                    if !editing { SoundService.preview("Pop", volume: Float(volume)) }
                }
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            VStack(alignment: .leading, spacing: 10) {
                Text("EVENTS")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary).kerning(0.5)
                ForEach(SoundEvent.allCases) { event in
                    HStack(spacing: 10) {
                        Toggle(event.label, isOn: bindingOn(event))
                            .toggleStyle(.checkbox)
                        Spacer()
                        Picker("", selection: bindingName(event)) {
                            ForEach(SoundService.available, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(width: 130)
                        Button { SoundService.preview(perEvent[event.rawValue]?.name ?? event.defaultSound, volume: Float(volume)) } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless).help("Preview")
                    }
                    .disabled(!enabled)
                }
            }

            Spacer()
            SaveBar(disabled: !isDirty) {
                d.set(enabled, forKey: PrefKey.soundsEnabled)
                d.set(volume, forKey: PrefKey.soundVolume)
                for e in SoundEvent.allCases {
                    if let v = perEvent[e.rawValue] {
                        d.set(v.on, forKey: e.enabledKey)
                        d.set(v.name, forKey: e.nameKey)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear(perform: load)
    }

    private func bindingOn(_ e: SoundEvent) -> Binding<Bool> {
        Binding(get: { perEvent[e.rawValue]?.on ?? true },
                set: { perEvent[e.rawValue, default: (true, e.defaultSound)].on = $0 })
    }
    private func bindingName(_ e: SoundEvent) -> Binding<String> {
        Binding(get: { perEvent[e.rawValue]?.name ?? e.defaultSound },
                set: { perEvent[e.rawValue, default: (true, e.defaultSound)].name = $0 })
    }
}

// MARK: - Vocabulary

private struct VocabularyTab: View {
    @ObservedObject var vocabulary: VocabularyStore
    @State private var newTerm = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Terms here bias recognition and are preserved during rewrite. Changes save immediately to a JSON file you can also hand-edit.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Add term (name, jargon, identifier)", text: $newTerm).onSubmit(add)
                Button("Add", action: add).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            List {
                ForEach(vocabulary.terms, id: \.self) { term in
                    HStack {
                        Text(term); Spacer()
                        Button(role: .destructive) { vocabulary.remove(term) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                Text(vocabulary.fileURL.path)
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    .help(vocabulary.fileURL.path)
                Spacer()
                Button("Reload") { vocabulary.reload() }
                Button("Reveal") { vocabulary.revealInFinder() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { vocabulary.reload() }
    }

    private func add() { vocabulary.add(newTerm); newTerm = "" }
}

// MARK: - Rewrite

private struct RewriteTab: View {
    @State private var enabled = d.bool(forKey: PrefKey.rewriteEnabled)
    @State private var provider = d.string(forKey: PrefKey.rewriteProvider) ?? RewriteProvider.anthropic.rawValue
    @State private var model = d.string(forKey: PrefKey.rewriteModel) ?? "claude-haiku-4-5-20251001"
    @State private var baseURL = d.string(forKey: PrefKey.rewriteBaseURL) ?? "https://api.openai.com/v1"
    @State private var prompt = d.string(forKey: PrefKey.rewritePrompt) ?? DefaultPref.rewritePromptTemplate
    @State private var apiKey = ""

    private var storedKey: String { Keychain.get(account: RewriteService.keychainAccount) ?? "" }
    private var isDirty: Bool {
        enabled != d.bool(forKey: PrefKey.rewriteEnabled)
        || provider != d.string(forKey: PrefKey.rewriteProvider)
        || model != d.string(forKey: PrefKey.rewriteModel)
        || baseURL != d.string(forKey: PrefKey.rewriteBaseURL)
        || prompt != (d.string(forKey: PrefKey.rewritePrompt) ?? DefaultPref.rewritePromptTemplate)
        || apiKey != storedKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Form {
                Toggle("Clean up transcript with an LLM", isOn: $enabled)
                Picker("Provider", selection: $provider) {
                    ForEach(RewriteProvider.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if provider == RewriteProvider.openaiCompatible.rawValue {
                    TextField("Base URL", text: $baseURL)
                }
                TextField("Model", text: $model)
                SecureField("API key (stored in Keychain)", text: $apiKey)
            }
            .frame(height: provider == RewriteProvider.openaiCompatible.rawValue ? 150 : 122)

            Text("User prompt — `{{input}}` is replaced with the transcript. Vocabulary and guardrails are added automatically via the system prompt.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $prompt)
                .font(.body.monospaced()).frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Button("Reset to default prompt") { prompt = DefaultPref.rewritePromptTemplate }
                .font(.caption).buttonStyle(.link)

            SaveBar(disabled: !isDirty) {
                d.set(enabled, forKey: PrefKey.rewriteEnabled)
                d.set(provider, forKey: PrefKey.rewriteProvider)
                d.set(model, forKey: PrefKey.rewriteModel)
                d.set(baseURL, forKey: PrefKey.rewriteBaseURL)
                d.set(prompt, forKey: PrefKey.rewritePrompt)
                Keychain.set(apiKey, account: RewriteService.keychainAccount)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { apiKey = storedKey }
    }
}

// MARK: - Permissions

private struct PermissionsTab: View {
    @ObservedObject var permissions: PermissionsManager
    @State private var confirmingReset = false

    var body: some View {
        Form {
            row("Microphone", granted: permissions.microphoneAuthorized,
                request: permissions.requestMicrophone, open: permissions.openMicrophoneSettings,
                note: "Required to record audio.")
            row("Accessibility", granted: permissions.accessibilityTrusted,
                request: permissions.requestAccessibility, open: permissions.openAccessibilitySettings,
                note: "Required to paste at the cursor.")
            row("Input Monitoring", granted: permissions.inputMonitoringGranted,
                request: permissions.requestInputMonitoring, open: permissions.openInputMonitoringSettings,
                note: "Required to use the fn / Globe key.")

            Divider()
            Text("After enabling Accessibility or Input Monitoring you must relaunch — macOS only applies these to a fresh launch. If a toggle won't stick, reset permissions to clear stale entries, then grant again.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Refresh") { permissions.refresh() }
                Button("Reset Permissions…") { confirmingReset = true }
                Spacer()
                Button("Quit & Relaunch") { permissions.quitAndRelaunch() }
                    .buttonStyle(.borderedProminent)
            }
            .confirmationDialog(
                "Reset all Looped Whisper permissions?",
                isPresented: $confirmingReset, titleVisibility: .visible
            ) {
                Button("Reset & Relaunch", role: .destructive) { permissions.resetAndRelaunch() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears Microphone, Accessibility, and Input Monitoring grants for the app, then relaunches so you can grant them fresh.")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { permissions.startMonitoring() }
        .onDisappear { permissions.stopMonitoring() }
    }

    private func row(_ title: String, granted: Bool, request: @escaping () -> Void,
                     open: @escaping () -> Void, note: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? BrandColor.success : BrandColor.error)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Grant", action: request); Button("Open Settings", action: open) }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - About

private struct AboutTab: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            Text("Looped Whisper").font(.title2).bold()
            Text(version).font(.caption).foregroundStyle(.secondary)
            Text("Free, open-source, local voice transcription for developers. Whisper models run on-device via WhisperKit — nothing is sent to the cloud for transcription.")
                .font(.callout).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            Link(destination: URL(string: "https://looped.sh")!) {
                Label("Learn more at looped.sh", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 16) {
                Link("WhisperKit", destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                Link("KeyboardShortcuts", destination: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!)
            }
            .font(.caption)
            Text("MIT License · © 2026 Looped Automation (Pty) Ltd")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
