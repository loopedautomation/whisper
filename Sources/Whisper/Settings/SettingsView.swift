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
            ActionsTab(store: coordinator.quickActions)
                .tabItem { Label("Actions", systemImage: "bolt") }
            PermissionsTab(permissions: coordinator.permissions)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AboutTab(coordinator: coordinator)
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
    @State private var showingLanguages = false
    @State private var languageRepairEnabled = d.bool(forKey: PrefKey.languageRepairEnabled)

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
        || languageRepairEnabled != d.bool(forKey: PrefKey.languageRepairEnabled)
    }

    private func toggle(_ code: String) {
        if languages.contains(code) { languages.remove(code) } else { languages.insert(code) }
    }

    private var languageCaption: String {
        switch languages.count {
        case 0: return "Auto-detects the language of each recording."
        case 1: return "Pinned — everything is transcribed as this language."
        default: return "Detects the language of each recording — only among your selection."
        }
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
            if WhisperModel.engine(for: selectedModel) == .parakeet {
                Text("Parakeet detects the spoken language automatically (25 European languages, including mixed speech) — the language selection and custom vocabulary below don't apply to it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top) {
                Text("Language").frame(width: 110, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    // A popover (not a Menu) so checking several languages in one
                    // pass works — macOS menus dismiss after every item click.
                    Button {
                        showingLanguages.toggle()
                    } label: {
                        HStack {
                            Text(WhisperLanguage.summary(for: languages))
                                .lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 220)
                    .popover(isPresented: $showingLanguages, arrowEdge: .bottom) {
                        LazyVGrid(
                            columns: [GridItem(.fixed(120), alignment: .leading),
                                      GridItem(.fixed(120), alignment: .leading)],
                            alignment: .leading, spacing: 6
                        ) {
                            ForEach(WhisperLanguage.known.filter { !$0.code.isEmpty }) { lang in
                                Toggle(lang.label, isOn: Binding(
                                    get: { languages.contains(lang.code) },
                                    set: { _ in toggle(lang.code) }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(12)
                    }

                    Text(languageCaption)
                        .font(.caption).foregroundStyle(.secondary)

                    if languages.count > 1 {
                        Toggle("Fix cross-language mix-ups with AI", isOn: $languageRepairEnabled)
                            .toggleStyle(.checkbox)
                        Text(languageRepairEnabled
                             ? "Sends the transcript to your Rewrite provider (Settings → Rewrite) to repair words transcribed in the wrong language, e.g. mid-sentence switches. Not applied during realtime incremental typing."
                             : "Off — mid-sentence language switches may come out garbled. Turning this on sends the transcript to your Rewrite provider to repair it; the app stays fully local otherwise.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 320, alignment: .leading)
                    }
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
                d.set(languageRepairEnabled, forKey: PrefKey.languageRepairEnabled)
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
            .onChange(of: provider) { old, new in
                // Switching providers swaps in that provider's default model,
                // unless the user has typed a custom one.
                guard let oldProvider = RewriteProvider(rawValue: old),
                      let newProvider = RewriteProvider(rawValue: new),
                      model == oldProvider.defaultModel || model.isEmpty else { return }
                model = newProvider.defaultModel
            }

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

// MARK: - Actions (voice quick actions)

private struct ActionsTab: View {
    @ObservedObject var store: QuickActionStore
    @State private var enabled = d.bool(forKey: PrefKey.quickActionsEnabled)
    @State private var llmFallback = d.bool(forKey: PrefKey.quickActionsLLMFallback)
    @State private var modifier = d.string(forKey: PrefKey.quickActionsModifier) ?? QuickActionModifier.command.rawValue
    @State private var editing: QuickAction?
    @State private var creating = false
    @State private var testResult: (id: UUID, ok: Bool, message: String)?

    /// Runs the action as if its trigger had been spoken; `{{query}}` targets
    /// get a sample query. Shows a transient pass/fail badge on the row.
    private func test(_ action: QuickAction) {
        let query = action.target.contains("{{query}}") ? "test" : nil
        switch QuickActionExecutor.execute(action, query: query) {
        case .success:
            testResult = (action.id, true, "Action ran")
        case .failure(let err):
            testResult = (action.id, false, [err.message, err.hint].compactMap { $0 }.joined(separator: " — "))
        }
        let shown = action.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if testResult?.id == shown { testResult = nil }
        }
    }

    private var hasAPIKey: Bool {
        !(Keychain.get(account: RewriteService.keychainAccount) ?? "").isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable voice quick actions", isOn: Binding(
                get: { enabled },
                set: { enabled = $0; d.set($0, forKey: PrefKey.quickActionsEnabled) }))
            Text("When a recording starts with one of your trigger phrases, the action runs instead of pasting text. Anything else is pasted as usual. Use {{query}} in a target to capture what you say after the trigger.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Hold to activate")
                Picker("", selection: Binding(
                    get: { modifier },
                    set: { modifier = $0; d.set($0, forKey: PrefKey.quickActionsModifier) })) {
                    ForEach(QuickActionModifier.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden().frame(width: 160)
            }
            .disabled(!enabled)
            Text(modifier == QuickActionModifier.none.rawValue
                 ? "Every recording is checked for quick actions."
                 : "Quick actions run only when this key is already held as recording starts (e.g. \(QuickActionModifier(rawValue: modifier)?.label.prefix(1) ?? "") then 🌐). Recordings without it always paste as dictation. Note: this works with the fn/Globe key — a standard shortcut won't fire with an extra modifier held, so pick “Always active” if you only use standard shortcuts.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Toggle("Use AI to detect intent when no trigger matches", isOn: Binding(
                get: { llmFallback },
                set: { llmFallback = $0; d.set($0, forKey: PrefKey.quickActionsLLMFallback) }))
                .disabled(!enabled || !hasAPIKey)
            Text(hasAPIKey
                 ? "Sends short transcripts to your Rewrite provider to recognize paraphrased commands like “could you pull up github”."
                 : "Requires an API key — configure one in the Rewrite tab.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(store.actions) { action in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { action.enabled },
                            set: { store.setEnabled(action, $0) }))
                            .toggleStyle(.checkbox).labelsHidden()
                        Image(systemName: action.kind.symbolName)
                            .foregroundStyle(.secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.name).fontWeight(.medium)
                            Text("“\(action.triggers.joined(separator: "”, “"))” → \(action.target)")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if testResult?.id == action.id {
                            Image(systemName: testResult!.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(testResult!.ok ? BrandColor.success : BrandColor.error)
                                .help(testResult!.message)
                        }
                        Button { test(action) } label: { Image(systemName: "play.circle") }
                            .buttonStyle(.borderless).help("Test this action now")
                        Button { editing = action } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help("Edit")
                        Button(role: .destructive) { store.remove(action) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .disabled(!enabled)

            HStack(spacing: 8) {
                Button("Add Action…") { creating = true }
                Spacer()
                Image(systemName: "doc.text")
                Text(store.fileURL.path)
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    .help(store.fileURL.path)
                Button("Reload") { store.reload() }
                Button("Reveal") { store.revealInFinder() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { store.reload() }
        .sheet(item: $editing) { action in
            QuickActionEditor(action: action) { store.update($0) }
        }
        .sheet(isPresented: $creating) {
            QuickActionEditor(action: QuickAction(name: "", triggers: [], kind: .openURL, target: "")) {
                store.add($0)
            }
        }
    }
}

private struct QuickActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (QuickAction) -> Void

    @State private var action: QuickAction
    @State private var triggersText: String

    init(action: QuickAction, onSave: @escaping (QuickAction) -> Void) {
        self.onSave = onSave
        _action = State(initialValue: action)
        _triggersText = State(initialValue: action.triggers.joined(separator: ", "))
    }

    private var parsedTriggers: [String] {
        triggersText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var valid: Bool {
        !action.name.trimmingCharacters(in: .whitespaces).isEmpty
        && !parsedTriggers.isEmpty
        && !action.target.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(action.name.isEmpty ? "New Action" : "Edit Action").font(.headline)
            Form {
                TextField("Name", text: $action.name, prompt: Text("Open GitHub"))
                TextField("Triggers", text: $triggersText, prompt: Text("take me to github, open github"))
                Picker("Action", selection: $action.kind) {
                    ForEach(QuickActionKind.allCases) { Text($0.label).tag($0) }
                }
                TextField("Target", text: $action.target, prompt: Text(action.kind.targetHint))
                    .font(.body.monospaced())
            }
            Text("Triggers are comma-separated spoken phrases. A trigger can also be a prefix — “search for cats” fills {{query}} with “cats”.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    action.triggers = parsedTriggers
                    onSave(action)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 440)
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
    @ObservedObject var coordinator: Coordinator
    @ObservedObject private var updates: UpdateChecker

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        self.updates = coordinator.updateChecker
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…").font(.caption).foregroundStyle(.secondary)
            }
        case .updateAvailable(let v, _):
            Button {
                updates.openDownloadPage()
            } label: {
                Label("Update available: \(v) — Download", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        case .upToDate:
            Text("You're up to date.").font(.caption).foregroundStyle(.secondary)
        case .failed:
            Text("Couldn't check for updates.").font(.caption).foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            Text("Looped Whisper").font(.title2).bold()
            Text(version).font(.caption).foregroundStyle(.secondary)

            updateStatus
            Button("Check for Updates…") { coordinator.checkForUpdates() }
                .controlSize(.small)

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
