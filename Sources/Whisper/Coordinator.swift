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
    let models: ModelManager
    let audioDevices: AudioDeviceManager

    private let recorder = AudioRecorder()
    private let transcription = TranscriptionService()
    private var hotkeys: HotkeyManager?
    private let fnMonitor = FnKeyMonitor()

    private var realtimeTimer: Timer?
    private var realtimeTask: Task<Void, Never>?
    private let hud: HUDPanelController
    private var escMonitorGlobal: Any?
    private var escMonitorLocal: Any?

    init() {
        // Install crash handlers as early as possible so we catch failures during
        // the rest of startup too. Purely local; nothing is sent anywhere.
        CrashReporter.install()
        let state = AppState()
        self.state = state
        permissions = PermissionsManager()
        loginItem = LoginItemManager()
        vocabulary = VocabularyStore()
        models = ModelManager()
        audioDevices = AudioDeviceManager()
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
        state.hasPendingCrashLogs = CrashReporter.hasPendingLogs()
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
                language: self.language(),
                vocabulary: self.vocabulary.terms
            )
            if let text, !Task.isCancelled {
                self.state.liveHypothesis = text
            }
            self.realtimeTask = nil
        }
    }

    // MARK: - pipeline tail

    private func finishPipeline(samples: [Float]) async {
        do {
            let raw = try await transcription.transcribe(
                samples: samples,
                language: language(),
                vocabulary: vocabulary.terms
            )
            state.liveConfirmed = raw

            var finalText = raw
            if UserDefaults.standard.bool(forKey: PrefKey.rewriteEnabled), let cfg = rewriteConfig() {
                state.setStatus(.rewriting)
                let outcome = await RewriteService.rewriteResult(raw, vocabulary: vocabulary.terms, config: cfg)
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
            TextInserter.insert(text, restoreClipboard: restore)
        }
    }

    // MARK: - helpers

    private func currentMode() -> TranscriptionMode {
        TranscriptionMode(rawValue: UserDefaults.standard.string(forKey: PrefKey.transcriptionMode) ?? "") ?? .batch
    }

    private func language() -> String {
        UserDefaults.standard.string(forKey: PrefKey.language) ?? ""
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
