import Foundation
import SwiftUI
import AVFoundation
import AppKit

/// Orchestrates the full capture pipeline:
/// record → (realtime live caption) → transcribe → (rewrite) → clipboard/paste.
@MainActor
final class Coordinator: ObservableObject {
    let state: AppState
    let permissions: PermissionsManager
    let loginItem: LoginItemManager
    let vocabulary: VocabularyStore
    let quickActions: QuickActionStore
    let models: ModelManager
    let audioDevices: AudioDeviceManager
    let updateChecker: UpdateChecker

    private let recorder = AudioRecorder()
    private let transcription = TranscriptionService()
    private var hotkeys: HotkeyManager?
    private let fnMonitor = FnKeyMonitor()

    private var realtimeTimer: Timer?
    private var realtimeTask: Task<Void, Never>?
    private let hud: HUDPanelController
    private var escMonitorGlobal: Any?
    private var escMonitorLocal: Any?
    // Incremental (live) insertion state for realtime mode.
    private var incrementalActive = false
    private var liveInsertedText = ""
    private var lastPollText = ""
    // Language detected once per recording when several languages are selected
    // (restricted mode); pinned for the rest of the session.
    private var detectedLanguage: String?
    private var languageRechecked = false
    // The app the user was dictating into, captured the moment recording
    // starts. Re-activated right before every paste/type — transcription
    // (and optional language detection / AI rewrite) can take long enough
    // for focus to drift elsewhere before delivery, which otherwise sends
    // the keystrokes to whatever happens to be frontmost at that later
    // moment instead of the app the user was actually looking at.
    private var targetApp: NSRunningApplication?
    // Whether quick actions are armed for this recording: the configured
    // modifier was held the moment recording started (or none is required).
    private var quickActionsArmed = false
    // Holding the modifier is an explicit mode switch into action mode: if no
    // action matches, nothing is pasted (the transcript goes to the clipboard
    // instead). Only ever true when a modifier is configured — "Always active"
    // must keep falling through to paste or dictation would break.
    private var quickActionsForced = false

    init() {
        // Install crash handlers as early as possible so we catch failures during
        // the rest of startup too. Purely local; nothing is sent anywhere.
        CrashReporter.install()
        let state = AppState()
        self.state = state
        permissions = PermissionsManager()
        loginItem = LoginItemManager()
        vocabulary = VocabularyStore()
        quickActions = QuickActionStore()
        models = ModelManager()
        audioDevices = AudioDeviceManager()
        updateChecker = UpdateChecker()
        hud = HUDPanelController(state: state)
        bootstrap()
    }

    func bootstrap() {
        DefaultPref.registerDefaults()
        permissions.refresh()
        loginItem.refresh()
        HotkeyManager.installDefaultShortcutsIfNeeded()
        hotkeys = HotkeyManager(coordinator: self)
        hotkeys?.register()
        configureFnMonitor()
        preloadModelInBackground()
        checkForUpdatesInBackground()
        state.hasPendingCrashLogs = CrashReporter.hasPendingLogs()
    }

    // MARK: - updates

    /// Silent best-effort check at launch; failures are swallowed.
    private func checkForUpdatesInBackground() {
        Task { await updateChecker.check() }
    }

    /// User-initiated check from the menu; surfaces the result either way.
    func checkForUpdates() {
        Task {
            await updateChecker.check()
            switch updateChecker.state {
            case .upToDate:
                presentUpToDateAlert()
            case .failed:
                presentUpdateCheckFailedAlert()
            case .updateAvailable, .downloading, .readyToInstall, .installing, .checking, .idle:
                break   // surfaced inline in the menu / About tab
            }
        }
    }

    private func presentUpToDateAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Looped Whisper \(updateChecker.currentVersion) is the latest version."
        alert.runModal()
    }

    private func presentUpdateCheckFailedAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = "Please check your connection and try again, or visit the releases page."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Releases")
        if alert.runModal() == .alertSecondButtonReturn {
            updateChecker.openDownloadPage()
        }
    }

    // MARK: - crash reports

    /// Presents an alert offering to inspect, report, or dismiss crash logs that
    /// were captured on a previous run. The user is in full control of sharing.
    func presentPendingCrashReports() {
        let count = CrashReporter.pendingLogs().count
        guard count > 0 else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = count == 1
            ? "Looped Whisper crashed on a previous run"
            : "Looped Whisper crashed \(count) times on previous runs"
        alert.informativeText = """
        A local crash log was saved on your machine. Nothing has been sent anywhere — \
        you decide whether to share it. You can view the log, copy it, or open a \
        prefilled GitHub issue to help us fix it.

        macOS also keeps more detailed reports in ~/Library/Logs/DiagnosticReports.
        """
        alert.addButton(withTitle: "Report on GitHub…")
        alert.addButton(withTitle: "Copy Log")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Dismiss")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = CrashReporter.githubIssueURL() { NSWorkspace.shared.open(url) }
            dismissCrashReports()
        case .alertSecondButtonReturn:
            if let log = CrashReporter.mostRecentLogContents() { ClipboardService.set(log) }
        case .alertThirdButtonReturn:
            CrashReporter.revealInFinder()
        default:
            dismissCrashReports()
        }
    }

    func dismissCrashReports() {
        CrashReporter.clearLogs()
        state.hasPendingCrashLogs = false
    }

    // MARK: - fn key

    func configureFnMonitor() {
        fnMonitor.stop()
        guard UserDefaults.standard.bool(forKey: PrefKey.fnEnabled) else { return }
        // The fn/Globe key tap needs Input Monitoring; without it the shortcut
        // silently does nothing, so surface an actionable error.
        permissions.refresh()
        if !permissions.inputMonitoringGranted {
            state.setError(AppError(
                "Input Monitoring not granted",
                hint: "enable it in System Settings to use the fn/Globe shortcut"))
        }
        let mode = FnMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.fnMode) ?? "") ?? .holdPTT
        switch mode {
        case .holdPTT:
            fnMonitor.onDown = { [weak self] in self?.beginRecording() }
            fnMonitor.onUp = { [weak self] in self?.endRecording() }
            fnMonitor.onDoubleTap = nil
        case .doubleTapToggle:
            fnMonitor.onDown = nil
            fnMonitor.onUp = nil
            fnMonitor.onDoubleTap = { [weak self] in self?.toggleRecording() }
        }
        fnMonitor.start()
    }

    // MARK: - model

    private func preloadModelInBackground() {
        let model = UserDefaults.standard.string(forKey: PrefKey.selectedModel) ?? "base"
        Task {
            await loadModel(model)
        }
    }

    func loadModel(_ model: String) async {
        let label = WhisperModel.label(for: model)
        state.setStatus(.loadingModel(label))
        state.clearError()
        // Download with visible progress (in the Model tab) if not already present.
        if !models.isDownloaded(model) {
            let ok = await models.download(model)
            if !ok && !models.isDownloaded(model) {
                state.setError(AppError(
                    "Couldn't download the \(label) model",
                    hint: "check your internet connection and try again"))
                return
            }
        }
        do {
            try await transcription.loadModel(model) { _ in }
            if !state.isRecording { state.setStatus(.idle) }
        } catch {
            state.setError(AppError(
                "Couldn't load the \(label) transcription model",
                hint: "try re-downloading it in Settings → Model"))
        }
    }

    // MARK: - recording control

    func toggleRecording() {
        SoundService.play(.toggle)
        if state.isRecording { endRecording(silent: true) } else { beginRecording(silent: true) }
    }

    func beginRecording(silent: Bool = false) {
        guard !state.isRecording else { return }
        // TranscriptionService is an actor: starting a recording while it's
        // still finishing a previous transcribe/rewrite pass — or still
        // downloading/loading a newly-switched model — doesn't fail, it just
        // silently queues behind that work. The status line then gets
        // overwritten to "Recording…"/"Transcribing…", hiding what's actually
        // still happening, so it can look stuck for as long as that takes
        // (worst case: minutes, for a multi-GB model download). Refuse up
        // front with a specific reason instead.
        if state.isBusy {
            let reason: String
            switch state.status {
            case .loadingModel(let label): reason = "\(label) is still loading"
            case .transcribing: reason = "Still transcribing the previous recording"
            case .rewriting: reason = "Still cleaning up the previous recording"
            default: reason = "Still busy"
            }
            state.setError(AppError(reason, hint: "wait a moment and try again"))
            return
        }
        // Capture the dictation target before anything else — a permission
        // prompt below, or our own menu/HUD, could otherwise become
        // momentarily frontmost and get captured instead.
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = frontmost
        } else if targetApp?.isTerminated != false {
            // Don't hold on to a target from a previous session that has since
            // quit — refocusing it would silently fail and the paste would go
            // to whatever happens to be frontmost.
            targetApp = nil
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            // Permission was explicitly refused — the system prompt won't reappear,
            // so point the user at System Settings.
            state.setError(AppError(
                "Microphone access denied",
                hint: "enable it in System Settings → Privacy & Security → Microphone"))
            permissions.openMicrophoneSettings()
            return
        case .notDetermined:
            permissions.requestMicrophone()
            return
        default:
            break
        }
        do {
            try recorder.start()
            state.clearLive()
            state.lastWarning = nil
            state.clearError()
            state.setStatus(.recording)
            if !silent { SoundService.play(.start) }
            startEscMonitor()
            // Decide live-insertion up front so toggling the setting mid-session
            // can't corrupt what we type. Needs Accessibility (typing keystrokes).
            permissions.refresh()
            liveInsertedText = ""
            lastPollText = ""
            detectedLanguage = nil
            languageRechecked = false
            let modifier = QuickActionModifier(
                rawValue: UserDefaults.standard.string(forKey: PrefKey.quickActionsModifier) ?? "") ?? .command
            quickActionsForced = modifier != .none
                && NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(modifier.flags)
            quickActionsArmed = modifier == .none || quickActionsForced
            incrementalActive = currentMode() == .realtime
                && currentInsertion() == .incremental
                && permissions.accessibilityTrusted
            if currentMode() == .realtime {
                hud.show()
                startRealtimePolling()
            }
        } catch {
            state.setError(AppError("Couldn't start recording", hint: error.localizedDescription))
        }
    }

    func endRecording(silent: Bool = false) {
        guard state.isRecording else { return }
        stopEscMonitor()
        stopRealtimePolling()
        let samples = recorder.stop()
        if !silent { SoundService.play(.stop) }
        state.setStatus(.transcribing)
        Task { await finishPipeline(samples: samples) }
    }

    /// Esc: abort recording without transcribing, and hide the HUD.
    func cancelRecording() {
        guard state.isRecording else { return }
        stopEscMonitor()
        stopRealtimePolling()
        _ = recorder.stop()          // discard samples
        incrementalActive = false
        hud.hide()
        state.clearLive()
        state.setStatus(.idle)
    }

    // MARK: - Esc-to-cancel

    private func startEscMonitor() {
        guard escMonitorGlobal == nil else { return }
        // Global: Esc pressed while another app is focused (the usual dictation case).
        escMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.cancelRecording() } }
        }
        // Local: Esc pressed while our own window (e.g. the HUD) is focused.
        escMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelRecording(); return nil }
            return event
        }
    }

    private func stopEscMonitor() {
        if let m = escMonitorGlobal { NSEvent.removeMonitor(m); escMonitorGlobal = nil }
        if let m = escMonitorLocal { NSEvent.removeMonitor(m); escMonitorLocal = nil }
    }

    // MARK: - realtime polling

    private func startRealtimePolling() {
        realtimeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollRealtime() }
        }
    }

    private func stopRealtimePolling() {
        realtimeTimer?.invalidate()
        realtimeTimer = nil
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    private func pollRealtime() {
        guard realtimeTask == nil else { return }   // skip if previous pass still running
        let snapshot = recorder.snapshot()
        guard snapshot.count > Int(AudioRecorder.targetSampleRate) / 2 else { return }
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            let text = try? await self.transcription.transcribe(
                samples: snapshot,
                selection: await self.realtimeSelection(snapshot: snapshot),
                vocabulary: self.vocabulary.terms
            )
            if let text, !Task.isCancelled {
                self.state.liveHypothesis = text
                self.insertConfirmedDelta(from: text)
            }
            self.realtimeTask = nil
        }
    }

    /// Incremental insertion: a prefix that's identical across two consecutive
    /// transcription passes is treated as "confirmed" and typed at the cursor
    /// (only the part we haven't typed yet).
    private func insertConfirmedDelta(from text: String) {
        guard incrementalActive else { return }
        let stable = String(text.commonPrefix(with: lastPollText))
        lastPollText = text
        guard stable.count > liveInsertedText.count, stable.hasPrefix(liveInsertedText) else { return }
        // If nothing has keyboard focus right now, don't type — and don't mark
        // the delta as inserted, so it's retried on a later poll (or delivered
        // with the final remainder) instead of being lost.
        guard FocusInspector.focusStatus() != .noFocus else { return }
        let delta = String(stable.dropFirst(liveInsertedText.count))
        TextInserter.typeString(delta, targetApp: targetApp)
        liveInsertedText = stable
    }

    // MARK: - pipeline tail

    private func finishPipeline(samples: [Float]) async {
        do {
            // Always re-derive the selection fresh for the final decode — do
            // NOT reuse `detectedLanguage` from realtime polling. That cache
            // is only a rough guess from the first ~2s of audio (kept solely
            // to avoid re-detecting on every poll and to stop live captions
            // flip-flopping mid-recording); pinning the FINAL, complete-
            // recording decode to an early guess risks forcing the whole
            // transcript into the wrong language on a bad guess, which can
            // degrade output all the way down to nothing. Letting transcribe()
            // detect fresh here uses the full recording, same as batch mode
            // already does, which is far more reliable than a 2s snapshot.
            let raw = try await transcription.transcribe(
                samples: samples,
                selection: languageSelection(),
                vocabulary: vocabulary.terms
            )
            state.liveConfirmed = raw

            // Incremental live-insertion: we've already typed the confirmed prefix
            // during recording. Type only the final remainder, and skip rewrite
            // (it would reformat text already in the document).
            if incrementalActive {
                let remainder: String
                if raw.hasPrefix(liveInsertedText) {
                    remainder = String(raw.dropFirst(liveInsertedText.count))
                } else {
                    remainder = String(raw.dropFirst(raw.commonPrefix(with: liveInsertedText).count))
                }
                if !remainder.isEmpty && FocusInspector.focusStatus() == .noFocus {
                    // Nowhere for the keystrokes to land — put the full
                    // transcript on the clipboard rather than typing into
                    // the void, so nothing is lost.
                    ClipboardService.set(raw)
                    state.setError(AppError(
                        "Nothing was focused to type into (copied to clipboard instead)",
                        hint: "click where you want the text and press ⌘V"))
                } else {
                    TextInserter.typeString(remainder, targetApp: targetApp)
                }
                state.lastTranscript = raw
                SoundService.play(.done)
                if case .error = state.status {} else { state.setStatus(.idle) }
                hud.hide()
                state.clearLive()
                return
            }

            // Voice quick actions (opt-in): if the utterance matches a
            // user-defined command, run it instead of pasting anything.
            if quickActionsArmed, UserDefaults.standard.bool(forKey: PrefKey.quickActionsEnabled) {
                if let match = await resolveQuickAction(raw) {
                    state.lastTranscript = raw
                    switch QuickActionExecutor.execute(match.action, query: match.query) {
                    case .success:
                        SoundService.play(.done)
                        state.setStatus(.idle)
                    case .failure(let err):
                        state.setError(AppError(err.message, hint: err.hint))
                    }
                    hud.hide()
                    state.clearLive()
                    return
                }
                // Modifier held = explicit action mode. A miss must not paste —
                // the user signalled a command, not dictation.
                if quickActionsForced {
                    state.lastTranscript = raw
                    ClipboardService.set(raw)
                    state.setError(AppError(
                        "No quick action matched",
                        hint: "copied “\(raw.prefix(40))” to the clipboard instead"))
                    hud.hide()
                    state.clearLive()
                    return
                }
            }

            var finalText = raw
            let rewriteOn = UserDefaults.standard.bool(forKey: PrefKey.rewriteEnabled)
            let languageHint = languageRepairHint()
            // Language repair rides the same rewrite call so a recording never
            // pays for two LLM round-trips: if general rewrite is off, fall back
            // to a pass-through template so only the repair instruction applies.
            if rewriteOn || !languageHint.isEmpty, let cfg = rewriteConfig() {
                state.setStatus(.rewriting)
                let effectiveConfig = rewriteOn ? cfg : RewriteService.Config(
                    provider: cfg.provider, model: cfg.model, apiKey: cfg.apiKey,
                    promptTemplate: RewriteService.languageRepairOnlyTemplate, timeout: cfg.timeout)
                let outcome = await RewriteService.rewriteResult(
                    raw, vocabulary: vocabulary.terms, config: effectiveConfig, languageHint: languageHint)
                if let failure = outcome.failure {
                    // Rewrite failed: deliver the raw transcript but tell the user why.
                    state.setError(AppError(failure, hint: "delivered the raw transcript instead"))
                }
                finalText = outcome.text
            }

            state.lastTranscript = finalText
            deliver(finalText)
            SoundService.play(.done)
            if case .error = state.status {} else { state.setStatus(.idle) }
        } catch let error as TranscriptionService.TranscriptionError {
            switch error {
            case .empty:
                // Benign: nothing was said. Keep this a soft warning, not an error.
                state.setStatus(.idle)
                state.lastWarning = "No speech detected."
            case .modelNotLoaded:
                state.setError(AppError(
                    "Transcription model isn't ready",
                    hint: "wait for it to finish loading, or pick one in Settings → Model"))
            }
        } catch {
            state.setError(AppError("Transcription failed", hint: error.localizedDescription))
        }
        hud.hide()
        state.clearLive()
    }

    private func deliver(_ text: String) {
        guard !text.isEmpty else { return }
        let behavior = OutputBehavior(rawValue: UserDefaults.standard.string(forKey: PrefKey.outputBehavior) ?? "") ?? .copyPaste
        switch behavior {
        case .copyOnly:
            ClipboardService.set(text)
        case .copyPaste:
            permissions.refresh()
            guard permissions.accessibilityTrusted else {
                // Paste needs Accessibility; the text is already on the clipboard,
                // so degrade gracefully and tell the user how to enable auto-paste.
                ClipboardService.set(text)
                state.setError(AppError(
                    "Couldn't auto-paste (copied to clipboard instead)",
                    hint: "grant Accessibility in System Settings → Privacy & Security"))
                permissions.openAccessibilitySettings()
                return
            }
            let restore = UserDefaults.standard.bool(forKey: PrefKey.restoreClipboard)
            TextInserter.insert(text, restoreClipboard: restore, targetApp: targetApp) { [weak self] result in
                Task { @MainActor in
                    guard result == .copiedOnly else { return }
                    self?.state.setError(AppError(
                        "Nothing was focused to paste into (copied to clipboard instead)",
                        hint: "click where you want the text and press ⌘V"))
                }
            }
        }
    }

    // MARK: - helpers

    private func currentMode() -> TranscriptionMode {
        TranscriptionMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.transcriptionMode) ?? "") ?? .batch
    }

    private func currentInsertion() -> RealtimeInsertion {
        RealtimeInsertion(rawValue: UserDefaults.standard.string(forKey: PrefKey.realtimeInsertion) ?? "") ?? .onStop
    }

    private func selectedLanguageCodes() -> Set<String> {
        let stored = UserDefaults.standard.string(forKey: PrefKey.preferredLanguages)
            ?? UserDefaults.standard.string(forKey: PrefKey.language)   // migrate legacy pref
            ?? ""
        return WhisperLanguage.codes(from: stored)
    }

    private func languageSelection() -> LanguageSelection {
        WhisperLanguage.selection(for: selectedLanguageCodes())
    }

    /// Language labels to hand `RewriteService` for cross-language repair.
    /// Opt-in (sends the transcript to the user's configured Rewrite provider)
    /// and only meaningful with 2+ languages selected — `[]` otherwise, so the
    /// app stays fully local unless the user turns this on.
    private func languageRepairHint() -> [String] {
        guard UserDefaults.standard.bool(forKey: PrefKey.languageRepairEnabled) else { return [] }
        let codes = selectedLanguageCodes()
        guard codes.count > 1 else { return [] }
        return WhisperLanguage.labels(for: codes)
    }

    /// Language policy for a realtime pass. Polling re-transcribes the whole
    /// buffer every ~1.5 s, and re-detecting on each pass could flip the
    /// language mid-recording and corrupt incremental insertion — so in
    /// restricted mode the language is detected once (after ~2 s of audio)
    /// and pinned. A 2 s guess is fragile for bilingual speakers (an opening
    /// loanword or filler can pin the wrong language for the whole recording),
    /// so the guess is re-verified exactly once against the fuller buffer at
    /// ~6 s and corrected if it disagrees. Incremental insertion tolerates the
    /// one-time flip: the confirmed-prefix logic simply stops extending until
    /// the new decode overtakes what was already typed.
    private func realtimeSelection(snapshot: [Float]) async -> LanguageSelection {
        let selection = languageSelection()
        guard case .restricted(let candidates) = selection else { return selection }
        let rate = Int(AudioRecorder.targetSampleRate)
        if let cached = detectedLanguage {
            if !languageRechecked && snapshot.count >= rate * 6 {
                languageRechecked = true
                if let rechecked = try? await transcription.detectLanguage(samples: snapshot, among: candidates),
                   !rechecked.isEmpty {
                    detectedLanguage = rechecked
                    return .pinned(rechecked)
                }
            }
            return .pinned(cached)
        }
        guard snapshot.count >= rate * 2 else { return .auto }
        guard let detected = try? await transcription.detectLanguage(samples: snapshot, among: candidates),
              !detected.isEmpty else { return .auto }
        detectedLanguage = detected
        return .pinned(detected)
    }

    /// Hybrid quick-action detection: instant local trigger match first, then
    /// (opt-in, short utterances only) LLM intent classification via the
    /// configured Rewrite provider. Nil means "ordinary dictation — paste it".
    private func resolveQuickAction(_ transcript: String) async -> QuickActionMatcher.Match? {
        let actions = quickActions.actions
        guard actions.contains(where: \.enabled) else { return nil }
        if let local = QuickActionMatcher.match(transcript, actions: actions) {
            return local
        }
        guard UserDefaults.standard.bool(forKey: PrefKey.quickActionsLLMFallback),
              transcript.count < 200,   // long dictation is never a command
              let cfg = rewriteConfig() else { return nil }
        state.setStatus(.rewriting)
        guard let match = await QuickActionClassifier.classify(transcript, actions: actions, config: cfg),
              let action = actions.first(where: { $0.id == match.actionID }) else { return nil }
        return QuickActionMatcher.Match(action: action, query: match.query)
    }

    private func rewriteConfig() -> RewriteService.Config? {
        let key = Keychain.get(account: RewriteService.keychainAccount) ?? ""
        guard !key.isEmpty else { return nil }
        let providerPref = RewriteProvider(rawValue: UserDefaults.standard.string(forKey: PrefKey.rewriteProvider) ?? "") ?? .anthropic
        let model = UserDefaults.standard.string(forKey: PrefKey.rewriteModel) ?? "claude-haiku-4-5-20251001"
        let template = UserDefaults.standard.string(forKey: PrefKey.rewritePrompt) ?? DefaultPref.rewritePromptTemplate
        let provider: RewriteService.Provider
        switch providerPref {
        case .anthropic:
            provider = .anthropic
        case .openaiCompatible:
            let base = UserDefaults.standard.string(forKey: PrefKey.rewriteBaseURL) ?? "https://api.openai.com/v1"
            provider = .openaiCompatible(baseURL: base)
        }
        return RewriteService.Config(provider: provider, model: model, apiKey: key, promptTemplate: template)
    }
}
