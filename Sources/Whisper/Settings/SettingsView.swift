import SwiftUI
import KeyboardShortcuts

private let d = UserDefaults.standard

// MARK: - Shell

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, model, hotkeys, sounds, vocabulary, history, ai, actions, style, status, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .model:       return "Model"
        case .hotkeys:     return "Hotkeys"
        case .sounds:      return "Sounds"
        case .vocabulary:  return "Vocabulary"
        case .history:     return "History"
        case .ai:          return "Provider"
        case .actions:     return "Actions"
        case .style:       return "Rewrite style"
        case .status:      return "Status"
        case .permissions: return "Permissions"
        case .about:       return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general:     return "gear"
        case .model:       return "waveform"
        case .hotkeys:     return "keyboard"
        case .sounds:      return "speaker.wave.2"
        case .vocabulary:  return "character.book.closed"
        case .history:     return "clock.arrow.circlepath"
        case .ai:          return "wand.and.stars"
        case .actions:     return "bolt"
        case .style:       return "textformat"
        case .status:      return "menubar.rectangle"
        case .permissions: return "lock.shield"
        case .about:       return "info.circle"
        }
    }

    /// The sidebar's sections, in order.
    static let sections: [(title: String, panes: [SettingsPane])] = [
        ("Dictation", [.general, .model, .hotkeys, .sounds, .vocabulary, .history]),
        ("AI",        [.ai, .actions, .style]),
        ("App",       [.status, .permissions, .about]),
    ]

    /// One line under the page title, where the page needs introducing.
    var subtitle: String? {
        switch self {
        case .vocabulary:
            return "Terms here bias recognition and are preserved during rewrite. Changes save immediately to a JSON file you can also hand-edit."
        case .history:
            return "Everything you have dictated, kept on this Mac. Correct a transcript to what you meant and the app learns from it."
        case .ai:
            return "Used by everything that calls a model: rewriting a selection, language repair, and quick-action matching."
        case .style:
            return "Select text in any app, hold the Rewrite shortcut, and say what you want. The selection is replaced in place."
        case .status:
            return "The icon in your menu bar changes colour to show what Looped Whisper is doing."
        default:
            return nil
        }
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: Coordinator
    @State private var pane: SettingsPane = .general
    @AppStorage("settingsSidebarCollapsed") private var sidebarCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            rail
            Rectangle().fill(Looped.rule).frame(height: 1)
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Looped.rule).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .font(.sans(13))
        .foregroundStyle(Looped.ink)
        .tint(Looped.accentFill)
        .background(Looped.paper)
        .containerBackground(Looped.paper, for: .window)
        .navigationTitle("Whisper")
        .toolbar(removing: .title)   // the rail carries the name
        .railTitlebar()
    }

    /// The Looped rail header (brand.looped.sh, Patterns/App header "Rail"):
    /// a slim bar across the window with the app name centred in spaced mono.
    /// It sits under the title bar, so the window controls rest in its left
    /// edge and the whole bar drags the window.
    private var rail: some View {
        Text("WHISPER")
            .font(.mono(11, bold: true)).tracking(3.3)
            .foregroundStyle(Looped.ink)
            .frame(maxWidth: .infinity)
            .frame(height: Looped.railHeight)
            .accessibilityHidden(true)
    }

    /// The app sidebar rail: items run edge to edge, and it collapses to an
    /// icon rail from the toggle in its foot (or ⌘B).
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(SettingsPane.sections.enumerated()), id: \.offset) { index, section in
                        // Collapsed, the labels go and a rule stands between sections.
                        if sidebarCollapsed {
                            if index > 0 {
                                Rectangle().fill(Looped.rule).frame(height: 1)
                                    .padding(.vertical, 12)
                            }
                        } else {
                            Text(section.title.uppercased())
                                .font(.mono(9)).tracking(1)
                                .foregroundStyle(Looped.ink3)
                                .padding(.horizontal, 20)
                                .padding(.top, index > 0 ? 24 : 0)
                                .padding(.bottom, 8)
                                .accessibilityAddTraits(.isHeader)
                        }
                        VStack(spacing: 2) {
                            ForEach(section.panes) { item in
                                SidebarItem(pane: item, selected: pane == item,
                                            collapsed: sidebarCollapsed) { pane = item }
                            }
                        }
                    }
                }
                .padding(.top, 20)
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(Looped.rule).frame(height: 1)
            HStack(spacing: 9) {
                if !sidebarCollapsed {
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.mono(9)).tracking(0.2)
                        .foregroundStyle(Looped.ink3)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                SidebarToggle(collapsed: sidebarCollapsed) {
                    withAnimation(.easeInOut(duration: 0.16)) { sidebarCollapsed.toggle() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, sidebarCollapsed ? 0 : 20)
            .frame(height: Looped.footHeight)
        }
        .frame(width: sidebarCollapsed ? 56 : 218)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pane.title)
                .font(.sans(24, weight: 500)).tracking(-0.7)
                .foregroundStyle(Looped.ink)
            if let subtitle = pane.subtitle {
                Text(subtitle).lpCaption().frame(maxWidth: 480, alignment: .leading)
            }
        }
        .padding(.horizontal, Looped.gutter)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    @ViewBuilder private var content: some View {
        switch pane {
        case .general:     GeneralTab(coordinator: coordinator)
        case .model:       ModelTab(coordinator: coordinator)
        case .hotkeys:     HotkeysTab(coordinator: coordinator)
        case .sounds:      SoundsTab()
        case .vocabulary:  VocabularyTab(vocabulary: coordinator.vocabulary)
        case .history:     HistoryTab(coordinator: coordinator)
        case .ai:          AITab()
        case .actions:     ActionsTab(store: coordinator.quickActions)
        case .style:       StyleTab(style: coordinator.style, learner: coordinator.learner)
        case .status:      StatusTab(state: coordinator.state)
        case .permissions: PermissionsTab(permissions: coordinator.permissions)
        case .about:       AboutTab(coordinator: coordinator)
        }
    }
}

/// Selected: accent text and a small edge marker. Hover is flat shade on
/// selected and unselected items alike.
private struct SidebarItem: View {
    let pane: SettingsPane
    let selected: Bool
    let collapsed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .light))
                    .frame(width: 16)
                if !collapsed {
                    Text(pane.title)
                        .font(.sans(12, weight: selected ? 500 : 400))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selected ? Looped.accent : (hovering ? Looped.ink : Looped.ink2))
            .padding(.horizontal, collapsed ? 0 : 20).padding(.vertical, 10)
            .background(hovering ? Looped.shade : .clear)
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle().fill(Looped.accent)
                        .frame(width: 2).padding(.vertical, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(collapsed ? pane.title : "")
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The quiet square control in the sidebar's foot that collapses the rail.
private struct SidebarToggle: View {
    let collapsed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: collapsed ? "chevron.right.2" : "chevron.left.2")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(hovering ? Looped.ink : Looped.ink3)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 2)
                    .fill(hovering ? Looped.shade : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut("b", modifiers: .command)
        .help("\(collapsed ? "Expand" : "Collapse") sidebar · ⌘B")
        .accessibilityLabel(collapsed ? "Expand sidebar" : "Collapse sidebar")
    }
}

// MARK: - Saving

/// Settings save as they change; there is no Save button. A page puts one of
/// these at its foot with everything it edits as `key`.
private struct AutoSave<Key: Equatable>: View {
    let key: Key
    let save: () -> Void

    var body: some View {
        Color.clear.frame(height: 0)
            .onChange(of: key) { save() }
    }
}

/// A page's foot, for actions on the page as a whole. The same height as the
/// sidebar's foot, so the two rules meet in one line across the window.
private struct FooterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(spacing: 8) { content() }
                .padding(.horizontal, Looped.gutter)
                .frame(height: Looped.footHeight)
        }
    }
}

private func options<T: CaseIterable & RawRepresentable>(
    _ type: T.Type, label: (T) -> String
) -> [(value: String, label: String)] where T.RawValue == String {
    T.allCases.map { ($0.rawValue, label($0)) }
}

// MARK: - Status

/// A key to the menu bar icon: each state drawn exactly as the menu bar draws
/// it, with what it means. The state the app is in right now is marked.
private struct StatusTab: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private struct Row: Identifiable {
        let id: String
        let status: AppStatus
        let colour: String
        let title: String
        let meaning: String
    }

    private let rows = [
        Row(id: "idle", status: .idle, colour: "No colour", title: "Ready",
            meaning: "Nothing is happening. Hold your shortcut to start dictating."),
        Row(id: "recording", status: .recording, colour: "Orange", title: "Recording",
            meaning: "The microphone is on and Looped Whisper is listening, until you release the key or stop the recording. The same orange macOS shows while the microphone is in use."),
        Row(id: "working", status: .transcribing, colour: "Violet", title: "Transcribing",
            meaning: "Turning what you said into text on this Mac, or loading a model. A new recording can't start until this finishes."),
        Row(id: "rewriting", status: .rewriting, colour: "Green", title: "Rewriting",
            meaning: "Your AI model is rewriting a selection or repairing a transcript. With a hosted provider, this is the moment text leaves your Mac."),
        Row(id: "error", status: .error(""), colour: "Oxblood", title: "Needs attention",
            meaning: "Something went wrong. Open the menu to read what happened and how to fix it. The icon returns to normal after a few seconds."),
    ]

    private func isCurrent(_ row: Row) -> Bool {
        switch (row.status, state.status) {
        case (.idle, .idle), (.recording, .recording), (.error, .error), (.rewriting, .rewriting): return true
        case (.transcribing, .transcribing), (.transcribing, .loadingModel): return true
        default: return false
        }
    }

    var body: some View {
        PaneScroll {
            SettingSection("Menu bar icon") {
                ForEach(rows) { row in
                    HStack(alignment: .center, spacing: 18) {
                        Image(nsImage: MenuBarLabel.icon(for: row.status, dark: colorScheme == .dark))
                            .renderingMode(row.status == .idle ? .template : .original)
                            .foregroundStyle(Looped.ink)
                            .frame(width: 40, alignment: .leading)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(row.title).font(.sans(13, weight: 500)).foregroundStyle(Looped.ink)
                                Eyebrow(row.colour)
                                if isCurrent(row) { LoopedBadge("Now") }
                            }
                            Text(row.meaning).lpCaption()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                    Rule()
                }
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject private var loginItem: LoginItemManager

    @State private var outputBehavior = d.string(forKey: PrefKey.outputBehavior) ?? OutputBehavior.copyPaste.rawValue

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        self.loginItem = coordinator.loginItem
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneScroll {
                SettingSection("Startup") {
                    SettingRow("Launch at login",
                               caption: loginItem.requiresApproval
                                ? "Enable Looped Whisper in System Settings → General → Login Items." : nil) {
                        LoopedSwitch("Launch at login", isOn: Binding(
                            get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                    }
                }

                SettingSection("Output") {
                    SettingField("After transcribing") {
                        LoopedSelect(selection: $outputBehavior,
                                     options: options(OutputBehavior.self) { $0.label })
                            .frame(width: 240)
                    }
                }
            }
            AutoSave(key: outputBehavior) {
                d.set(outputBehavior, forKey: PrefKey.outputBehavior)
            }
        }
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
        VStack(spacing: 0) {
            PaneScroll {
                SettingSection("Recognition") {
                    SettingField("Active model",
                                 caption: WhisperModel.engine(for: selectedModel) == .parakeet
                                    ? "Parakeet detects the spoken language automatically (25 European languages, including mixed speech) — the language selection and custom vocabulary below don't apply to it."
                                    : nil) {
                        LoopedSelect(selection: $selectedModel,
                                     options: WhisperModel.known.map { ($0.id, $0.label) })
                            .frame(maxWidth: 320)
                    }
                    Rule()
                    SettingField("Language", caption: languageCaption) {
                        // A popover (not a Menu) so checking several languages in one
                        // pass works — macOS menus dismiss after every item click.
                        LoopedFieldButton(text: WhisperLanguage.summary(for: languages),
                                          isOpen: $showingLanguages)
                            .frame(maxWidth: 320)
                            .popover(isPresented: $showingLanguages, arrowEdge: .bottom) {
                                LazyVGrid(
                                    columns: [GridItem(.fixed(130), alignment: .leading),
                                              GridItem(.fixed(130), alignment: .leading)],
                                    alignment: .leading, spacing: 8
                                ) {
                                    ForEach(WhisperLanguage.known.filter { !$0.code.isEmpty }) { lang in
                                        Toggle(lang.label, isOn: Binding(
                                            get: { languages.contains(lang.code) },
                                            set: { _ in toggle(lang.code) }
                                        ))
                                        .toggleStyle(.loopedCheckbox)
                                    }
                                }
                                .padding(14)
                                .background(Looped.raised)
                            }
                    }

                    if languages.count > 1 {
                        Rule()
                        SettingRow("Fix cross-language mix-ups with AI",
                                   caption: languageRepairEnabled
                                    ? "Sends the transcript to your AI provider (Settings → AI) to repair words transcribed in the wrong language, e.g. mid-sentence switches. Not applied during realtime incremental typing."
                                    : "Off — mid-sentence language switches may come out garbled. Turning this on sends the transcript to your Rewrite provider to repair it; the app stays fully local otherwise.") {
                            LoopedSwitch("Fix cross-language mix-ups with AI", isOn: $languageRepairEnabled)
                        }
                    }
                }

                SettingSection("Downloads") {
                    PathRow(icon: "folder", path: models.baseURL.path) {
                        Button("Reveal") { models.revealBaseInFinder() }
                            .buttonStyle(.secondaryCompact)
                    }
                    Rule()
                    ForEach(WhisperModel.known) { model in
                        ModelRow(model: model, manager: models, activeModelID: selectedModel)
                        Rule()
                    }
                }
            }
            AutoSave(key: [selectedModel, WhisperLanguage.string(from: languages), String(languageRepairEnabled)]) {
                d.set(WhisperLanguage.string(from: languages), forKey: PrefKey.preferredLanguages)
                d.set(languageRepairEnabled, forKey: PrefKey.languageRepairEnabled)
                if selectedModel != d.string(forKey: PrefKey.selectedModel) {
                    d.set(selectedModel, forKey: PrefKey.selectedModel)
                    Task { await coordinator.loadModel(selectedModel) }
                }
            }
        }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.label).font(.sans(13, weight: 500))
                Text(model.note).lpCaption()
            }
            Spacer()
            trailing.frame(width: 200, alignment: .trailing)
        }
        .padding(.vertical, 10)
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
            HStack(spacing: 4) {
                LoopedBadge("Downloaded", tint: Looped.moss).padding(.trailing, 4)
                Button { manager.revealInFinder(model.id) } label: { Image(systemName: "folder") }
                    .buttonStyle(.icon).help("Reveal in Finder")
                Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.icon)
                    .disabled(isActive)
                    .help(isActive ? "Can’t delete the active model" : "Delete from disk")
            }
        case .notDownloaded:
            Button("Download") { manager.startDownload(model.id) }
                .buttonStyle(.secondaryCompact)
        case .downloading(let fraction):
            HStack(spacing: 8) {
                LoopedProgress(value: fraction, height: 6).frame(width: 70)
                Text("\(Int(fraction * 100))%")
                    .font(.mono(11)).foregroundStyle(Looped.ink2)
                    .frame(width: 34, alignment: .trailing)
                Button { manager.cancelDownload(model.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.icon).help("Cancel download")
            }
        case .failed(let message):
            HStack(spacing: 8) {
                LoopedBadge("Failed", tint: Looped.oxblood).help(message)
                Button("Retry") { manager.startDownload(model.id) }
                    .buttonStyle(.secondaryCompact).help(message)
            }
        }
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    @ObservedObject var coordinator: Coordinator
    @State private var fnEnabled = d.bool(forKey: PrefKey.fnEnabled)
    @State private var fnMode = d.string(forKey: PrefKey.fnMode) ?? FnMode.holdPTT.rawValue
    @State private var smartHotkey = d.bool(forKey: PrefKey.smartRewriteHotkey)
    @State private var smartFallback = d.string(forKey: PrefKey.smartRewriteFallback)
        ?? SmartHotkeyFallback.dictate.rawValue

    var body: some View {
        VStack(spacing: 0) {
            PaneScroll {
                SettingSection("Shortcuts") {
                    SettingRow("Push to talk", caption: "Hold to record; release to transcribe.") {
                        KeyboardShortcuts.Recorder(for: .pushToTalk)
                    }
                    Rule()
                    SettingRow("Toggle dictation", caption: "Press to start, press again to stop.") {
                        KeyboardShortcuts.Recorder(for: .toggleRecording)
                    }
                    Rule()
                    SettingRow("Rewrite selection", caption: "Hold while you say how to rewrite it.") {
                        KeyboardShortcuts.Recorder(for: .rewriteSelection)
                    }
                    Rule()
                    SettingRow("Paste last dictation", caption: "Pastes your most recent dictation again at the cursor.") {
                        KeyboardShortcuts.Recorder(for: .pasteLastDictation)
                    }
                    Rule()
                    HStack {
                        Text("Shortcuts save as you record them.").lpCaption()
                        Spacer()
                        Button("Reset to Defaults") { HotkeyManager.resetShortcutsToDefaults() }
                            .buttonStyle(.secondaryCompact)
                    }
                    .padding(.vertical, 10)
                }

                SettingSection("Smart push to talk") {
                    // Applied on the spot rather than on Save: a switch that looks
                    // like it took effect and didn't is worse than no switch.
                    SettingRow("Push-to-talk rewrites a selection",
                               caption: smartHotkey
                                ? "With this on, your push-to-talk key rewrites whatever text is selected and only dictates when nothing is — so you don't need a separate key. The selection is read through Accessibility, which doesn't touch your clipboard. Some apps (Electron ones especially) won't report their selection; the setting below decides what happens then. The dedicated Rewrite shortcut keeps working either way."
                                : "Your push-to-talk key always dictates. Turn this on to have it rewrite a selection instead when you have text selected.") {
                        LoopedSwitch("Push-to-talk rewrites a selection", isOn: $smartHotkey)
                    }
                    .onChange(of: smartHotkey) { _, new in
                        d.set(new, forKey: PrefKey.smartRewriteHotkey)
                    }
                    Rule()
                    SettingField("If an app won't say") {
                        LoopedSegmented(selection: $smartFallback,
                                        options: options(SmartHotkeyFallback.self) { $0.label })
                    }
                    .disabled(!smartHotkey)
                    .onChange(of: smartFallback) { _, new in
                        d.set(new, forKey: PrefKey.smartRewriteFallback)
                    }
                }

                SettingSection("fn / Globe key") {
                    SettingRow("Use the fn / Globe key") {
                        LoopedSwitch("Use the fn / Globe key", isOn: $fnEnabled)
                    }
                    Rule()
                    SettingField("fn action") {
                        LoopedSegmented(selection: $fnMode, options: options(FnMode.self) { $0.label })
                    }
                    .disabled(!fnEnabled)
                    Rule()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("macOS uses double-tap fn for Dictation — set System Settings → Keyboard → “Press 🌐 to” → Do Nothing to avoid conflicts. The fn key may not work on non-Apple keyboards, so keep a standard shortcut as a fallback.")
                            .lpCaption()
                        Button("Open Keyboard Settings") { coordinator.permissions.openKeyboardSettings() }
                            .buttonStyle(.secondaryCompact)
                            .disabled(!fnEnabled)
                    }
                    .padding(.vertical, 12)
                }
            }
            AutoSave(key: [String(fnEnabled), fnMode]) {
                d.set(fnEnabled, forKey: PrefKey.fnEnabled)
                d.set(fnMode, forKey: PrefKey.fnMode)
                coordinator.configureFnMonitor()
            }
        }
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

    /// Everything on the page, as one value to watch for changes.
    private var soundsSignature: String {
        "\(enabled)|\(volume)|" + SoundEvent.allCases.map { e in
            "\(perEvent[e.rawValue]?.on ?? true):\(perEvent[e.rawValue]?.name ?? e.defaultSound)"
        }.joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneScroll {
                SettingSection("Playback") {
                    SettingRow("Play sound effects") {
                        LoopedSwitch("Play sound effects", isOn: $enabled)
                    }
                    Rule()
                    SettingRow("Volume") {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill")
                            Slider(value: $volume, in: 0...1) { editing in
                                if !editing { SoundService.preview("Pop", volume: Float(volume)) }
                            }
                            .frame(width: 200)
                            Image(systemName: "speaker.wave.3.fill")
                        }
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Looped.ink3)
                    }
                    .disabled(!enabled)
                }

                SettingSection("Events") {
                    ForEach(SoundEvent.allCases) { event in
                        HStack(spacing: 10) {
                            Toggle(event.label, isOn: bindingOn(event))
                                .toggleStyle(.loopedCheckbox)
                            Spacer()
                            LoopedSelect(selection: bindingName(event),
                                         options: SoundService.available.map { ($0, $0) })
                                .frame(width: 140)
                            Button {
                                SoundService.preview(perEvent[event.rawValue]?.name ?? event.defaultSound,
                                                     volume: Float(volume))
                            } label: {
                                Image(systemName: "play")
                            }
                            .buttonStyle(.icon).help("Preview")
                        }
                        .padding(.vertical, 8)
                        .disabled(!enabled)
                        Rule()
                    }
                }
            }
            AutoSave(key: soundsSignature) {
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
        VStack(spacing: 0) {
            PaneScroll {
                SettingField("Add term") {
                    HStack(spacing: 8) {
                        LoopedField(placeholder: "Name, jargon, identifier", text: $newTerm, onSubmit: add)
                        Button("Add", action: add)
                            .buttonStyle(.primaryCompact)
                            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.top, 10)

                SettingSection("\(vocabulary.terms.count) \(vocabulary.terms.count == 1 ? "term" : "terms")") {
                    if vocabulary.terms.isEmpty {
                        EmptyState(title: "No terms yet",
                                   message: "Add names and jargon the model tends to mishear.")
                    }
                    ForEach(vocabulary.terms, id: \.self) { term in
                        HStack {
                            Text(term).font(.sans(13))
                            Spacer()
                            Button(role: .destructive) { vocabulary.remove(term) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.icon).help("Remove")
                        }
                        .padding(.vertical, 5)
                        Rule()
                    }
                }
            }
            FooterBar {
                PathRow(icon: "doc.text", path: vocabulary.fileURL.path) {
                    Button("Reload") { vocabulary.reload() }.buttonStyle(.secondaryCompact)
                    Button("Reveal") { vocabulary.revealInFinder() }.buttonStyle(.secondaryCompact)
                }
            }
        }
        .onAppear { vocabulary.reload() }
    }

    private func add() { vocabulary.add(newTerm); newTerm = "" }
}

// MARK: - History

/// The dictation log. Each entry can be copied, deleted, or corrected to what
/// was meant; corrections are what the app learns from.
private struct HistoryTab: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject private var history: DictationHistory
    @ObservedObject private var corrections: CorrectionStore
    @State private var search = ""
    @State private var editing: DictationHistory.Entry?
    @State private var confirmingClear = false
    @State private var shown = 50
    @State private var lastLearned: String?

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        self.history = coordinator.history
        self.corrections = coordinator.corrections
    }

    private var matches: [DictationHistory.Entry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            PaneScroll {
                if !corrections.replacements.isEmpty { learnedSection }

                SettingSection(history.entries.isEmpty ? "Dictations"
                               : "\(history.entries.count) \(history.entries.count == 1 ? "dictation" : "dictations")") {
                    if history.entries.isEmpty {
                        EmptyState(title: "Nothing dictated yet",
                                   message: "Each dictation appears here once it has been transcribed.")
                    } else {
                        LoopedField(placeholder: "Search", text: $search)
                            .padding(.vertical, 10)
                        Rule()
                        if matches.isEmpty {
                            EmptyState(title: "No matches", message: "No dictation contains “\(search)”.")
                        }
                        ForEach(matches.prefix(shown)) { entry in
                            row(entry)
                            Rule()
                        }
                        if matches.count > shown {
                            Button("Show \(min(50, matches.count - shown)) more") { shown += 50 }
                                .buttonStyle(.quietLink)
                                .padding(.vertical, 12)
                        }
                    }
                }
            }
            FooterBar {
                PathRow(icon: "doc.text", path: history.fileURL.path) {
                    Button("Reveal") { history.revealInFinder() }.buttonStyle(.secondaryCompact)
                    Button("Clear History…") { confirmingClear = true }
                        .buttonStyle(.destructiveCompact)
                        .disabled(history.entries.isEmpty)
                }
            }
        }
        .sheet(item: $editing) { entry in
            CorrectionEditor(entry: entry) { text in
                let learned = coordinator.correctDictation(entry.id, to: text)
                lastLearned = learned == 0 ? nil
                    : "Learned \(learned) \(learned == 1 ? "correction" : "corrections") from that."
            }
        }
        .confirmationDialog("Clear all dictation history?", isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the log of what you dictated. What the app has learned from your corrections is kept.")
        }
    }

    private func row(_ entry: DictationHistory.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Eyebrow(Self.stamp.string(from: entry.date))
                if entry.isCorrected { LoopedBadge("Corrected", tint: Looped.moss) }
                Spacer()
                Button("Correct") { editing = entry }.buttonStyle(.secondaryCompact)
                    .help("Rewrite this to what you meant, so the app learns from it")
                Button { ClipboardService.set(entry.text) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.icon).help("Copy")
                Button { history.delete(entry.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.icon).help("Delete")
            }
            Text(entry.text).font(.sans(13)).foregroundStyle(Looped.ink)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let original = entry.original {
                Text("Transcribed as: \(original)").lpCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
    }

    /// What correcting has taught the app, each one removable.
    private var learnedSection: some View {
        SettingSection("Learned corrections") {
            Text(lastLearned ?? "Applied to every new dictation. Remove one if it starts changing words it shouldn't.")
                .lpCaption().padding(.vertical, 10)
            Rule()
            ForEach(corrections.replacements) { item in
                HStack(spacing: 8) {
                    Text(item.heard).font(.mono(12)).foregroundStyle(Looped.ink2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Looped.ink3)
                    Text(item.meant).font(.mono(12)).foregroundStyle(Looped.ink)
                    Spacer()
                    Button { corrections.remove(item) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.icon).help("Stop making this correction")
                }
                .padding(.vertical, 7)
                Rule()
            }
        }
    }
}

/// Rewriting one dictation to what was meant.
private struct CorrectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DictationHistory.Entry
    let onSave: (String) -> Void
    @State private var text: String

    init(entry: DictationHistory.Entry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _text = State(initialValue: entry.text)
    }

    private var changed: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != entry.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Correct dictation")
                .font(.sans(20, weight: 500)).tracking(-0.5)
                .padding(.bottom, 6)
            Text("Change it to what you meant. Words you replace are fixed in future dictations, names join your vocabulary, and the rewrite model sees the correction.")
                .lpCaption().fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            TextEditor(text: $text)
                .font(.sans(13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 180)
                .background(RoundedRectangle(cornerRadius: Looped.radius).fill(Looped.paper))
                .overlay(RoundedRectangle(cornerRadius: Looped.radius).strokeBorder(Looped.ruleStrong))

            if let original = entry.original {
                Text("Transcribed as: \(original)").lpCaption()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save Correction") {
                    onSave(text)
                    dismiss()
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!changed)
            }
            .padding(.top, 14)
        }
        .padding(24)
        .frame(width: 520)
        .font(.sans(13))
        .foregroundStyle(Looped.ink)
        .background(Looped.paper)
    }
}

// MARK: - AI

/// The one model configuration in the app. Everything that needs an LLM —
/// rewriting a selection, repairing a cross-language mixup, classifying a quick
/// action — reads what's set here.
private struct AITab: View {
    @State private var provider = d.string(forKey: PrefKey.aiProvider) ?? RewriteProvider.anthropic.rawValue
    @State private var model = d.string(forKey: PrefKey.aiModel) ?? RewriteProvider.anthropic.defaultModel
    @State private var baseURL = d.string(forKey: PrefKey.aiBaseURL) ?? "http://localhost:11434/v1"
    @State private var apiKey = ""

    private var storedKey: String { Keychain.get(account: RewriteService.keychainAccount) ?? "" }
    var body: some View {
        VStack(spacing: 0) {
            PaneScroll {
                SettingSection("Provider") {
                    LoopedRadioGroup(selection: $provider,
                                     options: options(RewriteProvider.self) { $0.label })
                        .padding(.vertical, 12)
                        .onChange(of: provider) { old, new in
                            // Switching providers swaps in that provider's default model,
                            // unless the user has typed a custom one.
                            guard let oldProvider = RewriteProvider(rawValue: old),
                                  let newProvider = RewriteProvider(rawValue: new),
                                  model == oldProvider.defaultModel || model.isEmpty else { return }
                            model = newProvider.defaultModel
                        }

                    switch RewriteProvider(rawValue: provider) ?? .anthropic {
                    case .appleOnDevice:
                        onDeviceStatus
                    case .openaiCompatible:
                        LoopedAlert(tone: .info, title: "Stays on this machine if the server does",
                                    message: "Point this at a local server (Ollama, LM Studio) to keep your writing on this machine. The API key is optional here — it simply isn't sent when empty.")
                    case .anthropic:
                        LoopedAlert(tone: .warning, title: "Sent to Anthropic",
                                    message: "Your selections and transcripts are sent to Anthropic — switch to Apple Intelligence or a local server to keep them on this machine.")
                    }
                }

                // The on-device model has nothing to configure — showing empty
                // Model and API key boxes reads as "something is missing".
                if provider != RewriteProvider.appleOnDevice.rawValue {
                    SettingSection("Connection") {
                        if provider == RewriteProvider.openaiCompatible.rawValue {
                            SettingField("Base URL") {
                                LoopedField(placeholder: "http://localhost:11434/v1", text: $baseURL, mono: true)
                            }
                        }
                        SettingField("Model") {
                            LoopedField(placeholder: "Model name", text: $model, mono: true)
                        }
                        SettingField("API key", caption: "Stored in your Keychain.") {
                            LoopedField(placeholder: "API key", text: $apiKey, secure: true, mono: true)
                        }
                    }
                }
            }
            AutoSave(key: [provider, model, baseURL, apiKey]) {
                d.set(provider, forKey: PrefKey.aiProvider)
                d.set(model, forKey: PrefKey.aiModel)
                d.set(baseURL, forKey: PrefKey.aiBaseURL)
                if apiKey != storedKey { Keychain.set(apiKey, account: RewriteService.keychainAccount) }
            }
        }
        .onAppear { apiKey = storedKey }
    }

    /// Availability of Apple's on-device model, plus honest expectations. It is
    /// the private/free option, not the best one — saying so here is cheaper
    /// than a user concluding the feature got worse.
    @ViewBuilder
    private var onDeviceStatus: some View {
        let state = OnDeviceModelClient.availability()
        VStack(alignment: .leading, spacing: 12) {
            LoopedAlert(tone: state.isAvailable ? .success : .warning,
                        title: state.summary, message: state.recovery) {
                if state == .needsAppleIntelligence {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.secondaryCompact)
                    .padding(.top, 6)
                }
            }

            Text("Runs on this Mac: nothing is sent anywhere, no API key, works offline. It's a much smaller model than a hosted one — good for short everyday rewrites, weaker at matching your voice and at long or intricate instructions. Long selections won't fit and are reported rather than truncated.")
                .lpCaption()
        }
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
        VStack(spacing: 0) {
            PaneScroll {
                SettingSection {
                    SettingRow("Enable voice quick actions",
                               caption: "When a recording starts with one of your trigger phrases, the action runs instead of pasting text. Anything else is pasted as usual. Use {{query}} in a target to capture what you say after the trigger.") {
                        LoopedSwitch("Enable voice quick actions", isOn: Binding(
                            get: { enabled },
                            set: { enabled = $0; d.set($0, forKey: PrefKey.quickActionsEnabled) }))
                    }
                    Rule()
                    SettingField("Hold to activate",
                                 caption: modifier == QuickActionModifier.none.rawValue
                                    ? "Every recording is checked for quick actions."
                                    : "Quick actions run only when this key is already held as recording starts (e.g. \(QuickActionModifier(rawValue: modifier)?.label.prefix(1) ?? "") then 🌐). Recordings without it always paste as dictation. Note: this works with the fn/Globe key — a standard shortcut won't fire with an extra modifier held, so pick “Always active” if you only use standard shortcuts.") {
                        LoopedSelect(selection: Binding(
                            get: { modifier },
                            set: { modifier = $0; d.set($0, forKey: PrefKey.quickActionsModifier) }),
                                     options: options(QuickActionModifier.self) { $0.label })
                            .frame(width: 200)
                    }
                    .disabled(!enabled)
                    Rule()
                    SettingRow("Use AI to detect intent when no trigger matches",
                               caption: hasAPIKey
                                ? "Sends short transcripts to your AI provider to recognize paraphrased commands like “could you pull up github”."
                                : "Requires an API key — configure one in the AI tab.") {
                        LoopedSwitch("Use AI to detect intent when no trigger matches", isOn: Binding(
                            get: { llmFallback },
                            set: { llmFallback = $0; d.set($0, forKey: PrefKey.quickActionsLLMFallback) }))
                    }
                    .disabled(!enabled || !hasAPIKey)
                }

                SettingSection("Actions") {
                    if store.actions.isEmpty {
                        EmptyState(title: "No actions yet",
                                   message: "Add one to open a site, launch an app or run a search by voice.")
                    }
                    ForEach(store.actions) { action in
                        actionRow(action)
                        Rule()
                    }
                }
                .disabled(!enabled)
            }
            FooterBar {
                Button("Add Action…") { creating = true }.buttonStyle(.primaryCompact)
                PathRow(icon: "doc.text", path: store.fileURL.path) {
                    Button("Reload") { store.reload() }.buttonStyle(.secondaryCompact)
                    Button("Reveal") { store.revealInFinder() }.buttonStyle(.secondaryCompact)
                }
                .padding(.leading, 8)
            }
        }
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

    private func actionRow(_ action: QuickAction) -> some View {
        HStack(spacing: 10) {
            Toggle(action.name, isOn: Binding(
                get: { action.enabled },
                set: { store.setEnabled(action, $0) }))
                .toggleStyle(.loopedCheckbox).labelsHidden()
            Image(systemName: action.kind.symbolName)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Looped.ink3).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.name).font(.sans(13, weight: 500))
                Text("“\(action.triggers.joined(separator: "”, “"))” → \(action.target)")
                    .font(.mono(11)).foregroundStyle(Looped.ink2)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let result = testResult, result.id == action.id {
                LoopedBadge(result.ok ? "Ran" : "Failed",
                            tint: result.ok ? Looped.moss : Looped.oxblood)
                    .help(result.message)
            }
            Button { test(action) } label: { Image(systemName: "play") }
                .buttonStyle(.icon).help("Test this action now")
            Button { editing = action } label: { Image(systemName: "pencil") }
                .buttonStyle(.icon).help("Edit")
            Button(role: .destructive) { store.remove(action) } label: { Image(systemName: "trash") }
                .buttonStyle(.icon).help("Delete")
        }
        .padding(.vertical, 8)
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
        VStack(alignment: .leading, spacing: 0) {
            Text(action.name.isEmpty ? "New Action" : "Edit Action")
                .font(.sans(20, weight: 500)).tracking(-0.5)
                .padding(.bottom, 6)

            SettingField("Name") {
                LoopedField(placeholder: "Open GitHub", text: $action.name)
            }
            SettingField("Triggers",
                         caption: "Comma-separated spoken phrases. A trigger can also be a prefix — “search for cats” fills {{query}} with “cats”.") {
                LoopedField(placeholder: "take me to github, open github", text: $triggersText)
            }
            SettingField("Action") {
                LoopedSelect(selection: $action.kind,
                             options: QuickActionKind.allCases.map { ($0, $0.label) })
            }
            SettingField("Target") {
                LoopedField(placeholder: action.kind.targetHint, text: $action.target, mono: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    action.triggers = parsedTriggers
                    onSave(action)
                    dismiss()
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
            .padding(.top, 14)
        }
        .padding(24)
        .frame(width: 460)
        .font(.sans(13))
        .foregroundStyle(Looped.ink)
        .background(Looped.paper)
    }
}

// MARK: - Style (selection rewrite)

/// Status and configuration for "rewrite my selection". The rules themselves
/// live in a hand-edited `style.json`; this tab reports whether that file
/// parsed, shows what's currently in force, and points at the model settings.
private struct StyleTab: View {
    @ObservedObject var style: StyleStore
    @ObservedObject var learner: StyleLearner
    @State private var learningEnabled = d.bool(forKey: PrefKey.styleLearningEnabled)
    @State private var replacements: [String: String] = [:]

    var body: some View {
        PaneScroll {
            learningSection
            rulesSection

            VStack(alignment: .leading, spacing: 6) {
                Text("Note: rewriting works by copying the selection and pasting the result, so your clipboard ends up holding the rewrite.")
                    .lpCaption()
                Text("The model this uses is set in Settings → AI.")
                    .lpCaption()
            }
            .padding(.top, 16)
        }
        .onAppear {
            style.reload()
            learner.refreshProposals(profile: style.profile)
        }
    }

    private var rulesSection: some View {
        SettingSection("Rules · style.json") {
            VStack(alignment: .leading, spacing: 12) {
                if let error = style.loadError {
                    // A broken config disables the feature outright rather than
                    // falling back to defaults — a rule you think is on but isn't
                    // is the failure you'd never notice.
                    LoopedAlert(tone: .error, title: error,
                                message: "Rewriting is disabled until style.json parses.")
                } else if let config = style.config {
                    HStack(spacing: 8) {
                        LoopedBadge("Loaded", tint: Looped.moss)
                        Text("style.json parsed and in force.").lpCaption()
                    }

                    templatesSection(config)

                    let rules = SelectionRewriter.mechanicalRules(config.defaultProfile.enforced)
                    if rules.isEmpty {
                        Text("No enforced rules set.").lpCaption()
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Eyebrow("Enforced in code after every reply")
                            ForEach(rules, id: \.self) { rule in
                                Text("• \(rule)").font(.mono(11)).foregroundStyle(Looped.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)

            Rule()
            PathRow(icon: "doc.text", path: style.fileURL.path) {
                Button("Reload") { style.reload() }.buttonStyle(.secondaryCompact)
                Button("Reveal") { style.revealInFinder() }.buttonStyle(.secondaryCompact)
            }
        }
    }

    /// Templates, shown whether or not any exist.
    ///
    /// Hiding this when the list is empty is how the feature became invisible:
    /// anyone whose `style.json` predates templates never got the starter
    /// examples, so there was nothing on screen to reveal that templates were
    /// a thing at all.
    @ViewBuilder
    private func templatesSection(_ config: StyleConfig) -> some View {
        if config.templateNames.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Templates")
                Text("Separate profiles for different kinds of writing — an email voice, a Slack voice — each adding to your base rules. Name one while you speak (\"rewrite it as an email\"), or set a default here.")
                    .lpCaption()
                Button("Add example templates") { style.addExampleTemplates() }
                    .buttonStyle(.secondaryCompact)
                    .help("Adds Email and Slack templates to style.json, which you can then edit")
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow("Default template")
                LoopedSelect(selection: defaultTemplateBinding,
                             options: [("", StyleConfig.baseName)] + config.templateNames.map { ($0, $0) })
                    .frame(maxWidth: 320)
                Text("Used when you don't name one. Say \"rewrite it as \(config.templateNames[0].lowercased())\" to pick a different one for a single rewrite.")
                    .lpCaption()
                if StyleStore.exampleTemplates.contains(where: {
                    config.templates[$0.name.lowercased()] == nil
                }) {
                    Button("Add example templates") { style.addExampleTemplates() }
                        .buttonStyle(.quietLink)
                }
            }
        }
    }

    /// Writes the chosen default straight back into style.json — the file is
    /// the source of truth, so a picker that only changed a preference would
    /// disagree with what the user reads there.
    private var defaultTemplateBinding: Binding<String> {
        Binding(
            get: { style.config?.defaultTemplate ?? "" },
            set: { style.setDefaultTemplate($0.isEmpty ? nil : $0) })
    }

    // MARK: - learned style

    /// Rewriting is never blocked on the corpus — this just reports honestly
    /// which of the three states it's in, so "generic prose" is never mistaken
    /// for "your voice".
    private var learningSection: some View {
        SettingSection("Learned style") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: learner.readiness.symbolName)
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(learner.readiness == .matched ? Looped.moss : Looped.ink3)
                    Text(learner.readiness.label).font(.sans(16, weight: 500))
                }

                switch learner.readiness {
                case .generic:
                    Text("Rewrites run on style.json alone for now. Keep dictating and rewriting — your own writing is collected as you go.")
                        .lpCaption()
                case .learning(let have, let need, let needsMoreVariety):
                    // Clamped: `have` can exceed `need` when there's plenty of
                    // writing but it's all the same shape.
                    LoopedProgress(value: Double(min(have, need)), total: Double(need))
                    Text(needsMoreVariety
                         ? "Plenty of samples, but they're all a similar length. Dictating short notes and rewriting longer passages both help."
                         : "\(have) samples so far. Rewrites already use them where they fit the passage.")
                        .lpCaption()
                case .matched:
                    Text("Samples matching each passage are sent with every rewrite, along with your recent edits.")
                        .lpCaption()
                }
            }
            .padding(.vertical, 12)

            Rule()
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(StyleRegister.allCases.enumerated()), id: \.offset) { index, register in
                    if index > 0 { Rectangle().fill(Looped.rule).frame(width: 1).padding(.horizontal, 14) }
                    LoopedStat(label: register.label,
                               value: "\(learner.corpus.sampleCount(in: register))")
                }
                if !learner.corpus.corrections.isEmpty {
                    Rectangle().fill(Looped.rule).frame(width: 1).padding(.horizontal, 14)
                    LoopedStat(label: "Edits", value: "\(learner.corpus.corrections.count)")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)

            // Style is learned per language, so one global number would imply a
            // voice match that doesn't exist in a language with no samples.
            let languages = learner.corpus.languageCounts
            if languages.count > 1 {
                Rule()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(languages, id: \.language) { entry in
                        HStack(spacing: 6) {
                            let state = learner.readiness(in: entry.language)
                            Image(systemName: state.symbolName)
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(state == .matched ? Looped.moss : Looped.ink3)
                            Text("\(LanguageDetector.displayName(entry.language)): \(state.label.lowercased())")
                                .font(.sans(12))
                        }
                    }
                    Text("Samples are only used for passages in the same language — English samples would pull a German rewrite toward English rhythm.")
                        .lpCaption().padding(.top, 2)
                }
                .padding(.vertical, 12)
            }

            if !learner.proposals.isEmpty {
                Rule()
                proposalList.padding(.vertical, 12)
            }

            Rule()
            SettingRow("Learn my style as I use it",
                       caption: "Collects your dictation transcripts and the text you select, on this machine only. A few matching samples are sent with each rewrite — turning this off stops collection but keeps what's already learned.") {
                LoopedSwitch("Learn my style as I use it", isOn: $learningEnabled)
            }
            .onChange(of: learningEnabled) { _, new in
                d.set(new, forKey: PrefKey.styleLearningEnabled)
            }
            Rule()
            PathRow(icon: "doc.text", path: learner.fileURL.path) {
                Button("Reveal") { learner.revealInFinder() }.buttonStyle(.secondaryCompact)
                Button("Forget everything", role: .destructive) { learner.forgetEverything() }
                    .buttonStyle(.destructiveCompact)
            }
        }
    }

    /// Mined rules, offered for confirmation. Never applied on their own — a
    /// rule that switched itself on is as bad as one that silently didn't.
    private var proposalList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Suggested rules")
            ForEach(learner.proposals) { proposal in
                VStack(alignment: .leading, spacing: 6) {
                    Text(proposal.title).font(.sans(13, weight: 500))
                    Text(proposal.evidence).lpCaption()
                    HStack(spacing: 8) {
                        if proposal.acceptsReplacement {
                            // Supplying a replacement moves the rule from the
                            // tier that costs a retry into the one fixed in code.
                            LoopedField(placeholder: "replace with (optional)", text: Binding(
                                get: { replacements[proposal.id] ?? "" },
                                set: { replacements[proposal.id] = $0 }))
                                .frame(maxWidth: 200)
                        }
                        Button("Add rule") {
                            style.accept(proposal, replacement: replacements[proposal.id])
                            learner.refreshProposals(profile: style.profile)
                        }
                        .buttonStyle(.secondaryCompact)
                        Button("No thanks") { learner.dismissProposal(proposal) }
                            .buttonStyle(.quietLink)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Looped.radius).strokeBorder(Looped.rule))
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsTab: View {
    @ObservedObject var permissions: PermissionsManager
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 0) {
            PaneScroll {
                SettingSection("Access") {
                    row("Microphone", granted: permissions.microphoneAuthorized,
                        request: permissions.requestMicrophone, open: permissions.openMicrophoneSettings,
                        note: "Required to record audio.")
                    Rule()
                    row("Accessibility", granted: permissions.accessibilityTrusted,
                        request: permissions.requestAccessibility, open: permissions.openAccessibilitySettings,
                        note: "Required to paste at the cursor.")
                    Rule()
                    row("Input Monitoring", granted: permissions.inputMonitoringGranted,
                        request: permissions.requestInputMonitoring, open: permissions.openInputMonitoringSettings,
                        note: "Required to use the fn / Globe key.")
                    Rule()
                }

                SettingSection("Troubleshooting") {
                    Text("After enabling Accessibility or Input Monitoring you must relaunch — macOS only applies these to a fresh launch. If a toggle won't stick, reset permissions to clear stale entries, then grant again.")
                        .lpCaption().padding(.vertical, 12)
                }
            }
            FooterBar {
                Button("Refresh") { permissions.refresh() }.buttonStyle(.secondaryCompact)
                Button("Reset Permissions…") { confirmingReset = true }.buttonStyle(.destructiveCompact)
                Spacer()
                Button("Quit & Relaunch") { permissions.quitAndRelaunch() }
                    .buttonStyle(.primary)
            }
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
        .onAppear { permissions.startMonitoring() }
        .onDisappear { permissions.stopMonitoring() }
    }

    private func row(_ title: String, granted: Bool, request: @escaping () -> Void,
                     open: @escaping () -> Void, note: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sans(13, weight: 500))
                Text(note).lpCaption()
            }
            Spacer()
            LoopedBadge(granted ? "Granted" : "Not granted",
                        tint: granted ? Looped.moss : Looped.oxblood)
            if !granted {
                Button("Grant", action: request).buttonStyle(.secondaryCompact)
                Button("Open Settings", action: open).buttonStyle(.secondaryCompact)
            }
        }
        .padding(.vertical, 12)
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
            progress("Checking for updates…")
        case .updateAvailable(let v, _):
            Button {
                updates.openDownloadPage()
            } label: {
                Label("Update available: \(v) — Download", systemImage: "arrow.down")
            }
            .buttonStyle(.primary)
        case .downloading(let v):
            progress("Downloading update \(v)…")
        case .readyToInstall(let v):
            Button {
                updates.installAndRelaunch()
            } label: {
                Label("Restart to update to \(v)", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.primary)
        case .installing:
            progress("Installing update…")
        case .upToDate:
            Text("You're up to date.").lpCaption()
        case .failed:
            Text("Couldn't check for updates.").lpCaption()
        case .idle:
            EmptyView()
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text).lpCaption()
        }
    }

    var body: some View {
        PaneScroll {
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Looped Whisper").font(.sans(20, weight: 500)).tracking(-0.5)
                    Text(version.uppercased()).font(.mono(10)).tracking(0.6)
                        .foregroundStyle(Looped.ink3)
                    HStack(spacing: 10) {
                        Button("Check for Updates…") { coordinator.checkForUpdates() }
                            .buttonStyle(.secondaryCompact)
                        updateStatus
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.top, 18)

            Text("Free, open-source, local voice transcription for developers. Whisper models run on-device via WhisperKit — nothing is sent to the cloud for transcription.")
                .font(.sans(13)).foregroundStyle(Looped.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.top, 18)

            SettingSection("Links") {
                HStack(spacing: 16) {
                    Link(destination: URL(string: "https://looped.sh")!) {
                        Label("Learn more at looped.sh", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.primary)
                    Link("WhisperKit", destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                        .buttonStyle(.quietLink)
                    Link("KeyboardShortcuts", destination: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!)
                        .buttonStyle(.quietLink)
                }
                .padding(.vertical, 14)
            }

            Text("MIT License · © 2026 Looped Automation (Pty) Ltd")
                .font(.mono(10)).foregroundStyle(Looped.ink3)
                .padding(.top, 8)
        }
    }
}
