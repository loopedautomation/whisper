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
    let style: StyleStore
    let learner: StyleLearner
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
    // The app the user was dictating into, captured the moment recording
    // starts. Re-activated right before every paste/type — transcription
    // (and optional language detection / AI rewrite) can take long enough
    // for focus to drift elsewhere before delivery, which otherwise sends
    // the keystrokes to whatever happens to be frontmost at that later
    // moment instead of the app the user was actually looking at.
    private var targetApp: NSRunningApplication?
    // The last app that wasn't us, updated continuously. Deliberately separate
    // from `targetApp`: this one moves as the user switches apps, so it must
    // never be read at delivery time — only when *starting* an action from our
    // own menu, where the frontmost app is already us.
    private var lastFrontmostApp: NSRunningApplication?
    // Selection rewrite: the copy runs concurrently with recording so the mic
    // is live before the user starts speaking. Held here so the pipeline tail
    // can await whatever the copy produced.
    private var selectionTask: Task<String, Error>?
    private var selectionRewriteActive = false
    private var frontmostObserver: NSObjectProtocol?

    init() {
        let state = AppState()
        self.state = state
        permissions = PermissionsManager()
        loginItem = LoginItemManager()
        vocabulary = VocabularyStore()
        style = StyleStore()
        learner = StyleLearner()
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
        observeFrontmostApp()
        preloadModelInBackground()
        checkForUpdatesInBackground()
    }

    /// Tracks the last app that wasn't us, for the menu path only — opening our
    /// menu makes *us* frontmost, so by the time the menu item fires there is
    /// nothing useful to read from `NSWorkspace.frontmostApplication`.
    ///
    /// This deliberately does **not** touch `targetApp`. `targetApp` is captured
    /// once when an action starts and must stay put: transcription plus a model
    /// call can take tens of seconds, and if delivery followed the user's focus
    /// the rewrite would paste into whatever app they switched to meanwhile.
    private func observeFrontmostApp() {
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in self?.lastFrontmostApp = app }
        }
    }

    deinit {
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
        }
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
            case .updateAvailable, .checking, .idle:
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

    /// Records the app the user is working in, so keystrokes land there later
    /// even if focus drifts while we transcribe. Skips our own windows.
    private func captureTargetApp() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = frontmost
        } else {
            // We're frontmost (menu open, or a stray activation) — fall back to
            // the last app the user was actually in.
            targetApp = lastFrontmostApp
        }
    }

    /// True when the mic is usable right now. Otherwise surfaces the reason
    /// (or triggers the system prompt) and returns false.
    private func ensureMicrophoneAccess() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            // Permission was explicitly refused — the system prompt won't reappear,
            // so point the user at System Settings.
            state.setError(AppError(
                "Microphone access denied",
                hint: "enable it in System Settings → Privacy & Security → Microphone"))
            permissions.openMicrophoneSettings()
            return false
        case .notDetermined:
            permissions.requestMicrophone()
            return false
        default:
            return true
        }
    }

    func beginRecording(silent: Bool = false) {
        guard !state.isRecording, !selectionRewriteActive else { return }
        // Capture the dictation target before anything else — a permission
        // prompt below, or our own menu/HUD, could otherwise become
        // momentarily frontmost and get captured instead.
        captureTargetApp()
        guard ensureMicrophoneAccess() else { return }
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
        guard state.isRecording, !selectionRewriteActive else { return }
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
        // Abandon an in-flight selection rewrite too: the clipboard already
        // holds the copied selection, but nothing is pasted back.
        selectionRewriteActive = false
        selectionTask?.cancel()
        selectionTask = nil
        hud.hide()
        state.clearLive()
        state.setStatus(.idle)
    }

    // MARK: - selection rewrite

    /// Hotkey down: copy the selection and start listening for the instruction.
    ///
    /// Both happen at once. The copy needs up to a second of round-tripping
    /// through the other app's pasteboard, and making the user wait for it
    /// would clip the first word of whatever they say.
    func beginSelectionRewrite() {
        guard !state.isRecording, !selectionRewriteActive else { return }
        captureTargetApp()

        // Preflight everything that can fail before we take over the user's
        // clipboard, so a misconfiguration never costs them their clipboard.
        // Re-read the config first: it's hand-edited, and checking the copy
        // parsed at launch would run stale rules — or miss a typo entirely.
        style.reload()
        guard style.profile != nil else {
            state.setError(AppError(
                style.loadError ?? "style.json couldn't be read",
                hint: "fix it in Settings → Style, then try again"))
            return
        }
        guard selectionRewriteConfig() != nil else {
            state.setError(AppError(
                "No rewrite model configured",
                hint: "add an API key or a local model URL in Settings → Rewrite"))
            return
        }
        permissions.refresh()
        guard permissions.accessibilityTrusted else {
            // Reading a selection means synthesizing ⌘C into another app.
            state.setError(AppError(
                "Rewriting a selection needs Accessibility",
                hint: "grant it in System Settings → Privacy & Security"))
            permissions.openAccessibilitySettings()
            return
        }
        guard ensureMicrophoneAccess() else { return }

        do {
            try recorder.start()
            state.clearLive()
            state.lastWarning = nil
            state.clearError()
            state.setStatus(.recording)
            SoundService.play(.start)
            startEscMonitor()
            selectionRewriteActive = true
            detectedLanguage = nil
            incrementalActive = false          // never type live into a rewrite
            let app = targetApp
            selectionTask = Task { try await SelectionService.capture(targetApp: app) }
        } catch {
            state.setError(AppError("Couldn't start recording", hint: error.localizedDescription))
        }
    }

    /// Hotkey up: transcribe the instruction, rewrite, paste over the selection.
    func endSelectionRewrite() {
        guard selectionRewriteActive, state.isRecording else { return }
        stopEscMonitor()
        let samples = recorder.stop()
        SoundService.play(.stop)
        state.setStatus(.transcribing)
        Task { await finishSelectionRewrite(samples: samples) }
    }

    private func finishSelectionRewrite(samples: [Float]) async {
        defer {
            selectionRewriteActive = false
            selectionTask = nil
            state.clearLive()
        }

        // The selection is the thing we can't proceed without, so resolve it
        // first — a missing selection shouldn't cost a transcription.
        let selection: String
        do {
            selection = try await selectionTask?.value ?? ""
        } catch let error as SelectionService.SelectionError {
            state.setError(AppError(error.errorDescription ?? "Couldn't read the selection",
                                    hint: error.hint))
            return
        } catch {
            state.setError(AppError("Couldn't read the selection", hint: error.localizedDescription))
            return
        }

        let transcript: String
        do {
            transcript = try await transcription.transcribe(
                samples: samples,
                selection: languageSelection(),
                vocabulary: vocabulary.terms)
        } catch let error as TranscriptionService.TranscriptionError {
            switch error {
            case .empty:
                // Nothing said: the natural reading is a plain "rewrite it",
                // but silently guessing an instruction would be worse than
                // asking again, so stop and say so.
                state.setStatus(.idle)
                state.lastWarning = "Didn't catch an instruction — nothing was changed."
            case .modelNotLoaded:
                state.setError(AppError(
                    "Transcription model isn't ready",
                    hint: "wait for it to finish loading, or pick one in Settings → Model"))
            }
            return
        } catch {
            state.setError(AppError("Transcription failed", hint: error.localizedDescription))
            return
        }

        await applyRewrite(selection: selection, instruction: transcript)
    }

    /// Rewrite the selection with a **typed** instruction instead of a spoken
    /// one. Same pipeline from here on — the transcript is just a string, and
    /// nothing downstream cares where it came from. This is also what makes the
    /// feature usable (and demonstrable) without a working microphone.
    func promptForTypedRewrite() {
        guard !state.isRecording, !selectionRewriteActive else { return }
        style.reload()
        guard style.profile != nil else {
            state.setError(AppError(style.loadError ?? "style.json couldn't be read",
                                    hint: "fix it in Settings → Style, then try again"))
            return
        }
        guard selectionRewriteConfig() != nil else {
            state.setError(AppError("No rewrite model configured",
                                    hint: "set one up in Settings → Rewrite"))
            return
        }
        permissions.refresh()
        guard permissions.accessibilityTrusted else {
            state.setError(AppError(
                "Rewriting a selection needs Accessibility",
                hint: "grant it in System Settings → Privacy & Security"))
            permissions.openAccessibilitySettings()
            return
        }

        // `targetApp` is whatever was frontmost before our menu opened; both the
        // copy and the paste re-activate it, so the focus round-trip is fine.
        captureTargetApp()
        let app = targetApp
        // Claimed before the modal opens and held until the paste completes.
        // `alert.runModal()` spins a nested run loop in which the global
        // hotkeys still fire, so without this the user could start a dictation
        // mid-alert and end up with two pipelines writing the clipboard and
        // synthesizing paste keystrokes at once.
        selectionRewriteActive = true
        // Let the menu bar finish dismissing before opening the modal —
        // running it inline from the menu's own action leaves the alert
        // without key focus.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let instruction = self.askForInstruction() else {
                self.selectionRewriteActive = false
                return
            }
            Task {
                defer { self.selectionRewriteActive = false }
                do {
                    let selection = try await SelectionService.capture(targetApp: app)
                    await self.applyRewrite(selection: selection, instruction: instruction)
                } catch let error as SelectionService.SelectionError {
                    self.state.setError(AppError(
                        error.errorDescription ?? "Couldn't read the selection", hint: error.hint))
                } catch {
                    self.state.setError(AppError("Couldn't read the selection",
                                                 hint: error.localizedDescription))
                }
            }
        }
    }

    /// Modal prompt for the instruction. `nil` when the user cancels.
    private func askForInstruction() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Rewrite selection"
        alert.informativeText = "What should I do with it? For example: “make it shorter”, "
            + "“fix the typos”, or just “rewrite it”."
        alert.addButton(withTitle: "Rewrite")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "rewrite it"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty box is the same request as saying "rewrite it".
        return typed.isEmpty ? "rewrite it" : typed
    }

    /// Shared tail for the spoken and typed paths: normalize the instruction,
    /// rewrite, then paste. `instruction` is a raw transcript or typed text —
    /// nothing downstream cares which.
    func applyRewrite(selection: String, instruction: String) async {
        guard let profile = style.profile else {
            state.setError(AppError(style.loadError ?? "style.json couldn't be read",
                                    hint: "fix it in Settings → Style, then try again"))
            return
        }
        guard let config = selectionRewriteConfig() else {
            state.setError(AppError("No rewrite model configured",
                                    hint: "set one up in Settings → Rewrite"))
            return
        }

        // Either the user's own writing, or one of our rewrites they've since
        // edited. Recorded before the rewrite so the edit informs this call.
        learner.noteSelection(selection)

        state.setStatus(.rewriting)
        let command = CommandNormalizer.normalize(instruction)
        let resolved = learner.resolve(profile, for: selection)
        // Size the ceiling to the passage. A fixed budget truncates long
        // selections, and a truncated reply pasted over the original amputates
        // the tail of the user's text. ~4 chars per token, doubled for headroom
        // (an "expand this" rewrite is longer than its input), floored so short
        // passages still get room and capped to stay within model limits.
        let budget = min(max(4096, (selection.count / 4) * 2), 16_384)
        let outcome = await SelectionRewriter.rewrite(
            selection: selection,
            command: command,
            style: resolved) { system, user in
                try await RewriteService.complete(
                    system: system, user: user,
                    provider: config.provider, model: config.model, apiKey: config.apiKey,
                    maxTokens: budget)
            }

        switch outcome {
        case .failed(let reason):
            // Nothing usable came back, so nothing is pasted — the user's text
            // is left exactly as it was.
            state.setError(AppError(reason, hint: "your selection wasn't changed"))
        case .rewritten(let text, let unmetRules):
            state.lastTranscript = text
            // Remember what we pasted, so that if this text comes back as a
            // selection later with edits in it, the difference can be read as
            // a correction.
            learner.noteProduced(text)
            SelectionService.replaceSelection(with: text, targetApp: targetApp)
            SoundService.play(.done)
            if unmetRules.isEmpty {
                if case .error = state.status {} else { state.setStatus(.idle) }
            } else {
                // A rule the user asked for did not hold. Say so loudly — the
                // rewrite is still pasted, but never silently short of a rule.
                state.setError(AppError(
                    "Rewrite pasted, but \(unmetRules.count == 1 ? "a rule" : "\(unmetRules.count) rules") didn't hold",
                    hint: unmetRules.joined(separator: "; ")))
            }
        }
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
        let delta = String(stable.dropFirst(liveInsertedText.count))
        TextInserter.typeString(delta, targetApp: targetApp)
        liveInsertedText = stable
    }

    // MARK: - pipeline tail

    private func finishPipeline(samples: [Float]) async {
        do {
            // Reuse the language detected during realtime polling (same
            // recording); otherwise restricted detection runs inside transcribe.
            let selection: LanguageSelection =
                detectedLanguage.map { .pinned($0) } ?? languageSelection()
            let raw = try await transcription.transcribe(
                samples: samples,
                selection: selection,
                vocabulary: vocabulary.terms
            )
            state.liveConfirmed = raw
            // Your own words, in your own phrasing. Harvested *before* the LLM
            // cleanup below — the cleaned version is the model's prose, and
            // learning from it would teach the app to imitate itself.
            learner.harvestDictation(raw)

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
                TextInserter.typeString(remainder, targetApp: targetApp)
                state.lastTranscript = raw
                // Same reason as the batch path below: this text is now in the
                // document, and selecting it later must not be mistaken for
                // hand-typed prose — its punctuation is the transcriber's.
                learner.noteProduced(raw)
                SoundService.play(.done)
                if case .error = state.status {} else { state.setStatus(.idle) }
                hud.hide()
                state.clearLive()
                return
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
            // Remember what lands in the document. Without this, selecting a
            // previously-dictated (and LLM-cleaned) paragraph to rewrite would
            // classify it as the user's own writing and harvest the cleanup
            // model's prose — and its punctuation — into the corpus.
            learner.noteProduced(finalText)
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
            TextInserter.insert(text, restoreClipboard: restore, targetApp: targetApp)
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
    /// restricted mode the language is detected once (after ~2 s of audio,
    /// enough to trust the result) and pinned for the rest of the recording.
    private func realtimeSelection(snapshot: [Float]) async -> LanguageSelection {
        let selection = languageSelection()
        guard case .restricted(let candidates) = selection else { return selection }
        if let cached = detectedLanguage { return .pinned(cached) }
        guard snapshot.count >= Int(AudioRecorder.targetSampleRate) * 2 else { return .auto }
        guard let detected = try? await transcription.detectLanguage(samples: snapshot, among: candidates),
              !detected.isEmpty else { return .auto }
        detectedLanguage = detected
        return .pinned(detected)
    }

    /// Provider settings for the selection rewrite. Separate from the dictation
    /// cleanup config so the two can point at different models — a fast local
    /// one for transcript tidying, a stronger one for rewriting your prose (or
    /// the reverse, if the selection is private and should stay on-device).
    struct SelectionModel {
        var provider: RewriteService.Provider
        var model: String
        var apiKey: String
    }

    /// `nil` when nothing usable is configured, which the caller turns into an
    /// actionable error rather than a silent no-op.
    private func selectionRewriteConfig() -> SelectionModel? {
        let defaults = UserDefaults.standard
        let model = defaults.string(forKey: PrefKey.selectionRewriteModel) ?? ""
        guard !model.isEmpty else { return nil }
        let key = Keychain.get(account: RewriteService.keychainAccount) ?? ""
        let providerPref = RewriteProvider(
            rawValue: defaults.string(forKey: PrefKey.selectionRewriteProvider) ?? "") ?? .anthropic
        switch providerPref {
        case .anthropic:
            guard !key.isEmpty else { return nil }
            return SelectionModel(provider: .anthropic, model: model, apiKey: key)
        case .openaiCompatible:
            // Locally-hosted servers need a URL but usually no key, so an empty
            // key is fine here — it just isn't sent.
            let base = defaults.string(forKey: PrefKey.selectionRewriteBaseURL) ?? ""
            guard !base.isEmpty else { return nil }
            return SelectionModel(provider: .openaiCompatible(baseURL: base), model: model, apiKey: key)
        }
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
