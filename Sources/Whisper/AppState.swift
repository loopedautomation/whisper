import Foundation
import Combine
import SwiftUI

/// High-level recording / pipeline status surfaced in the menu bar and HUD.
enum AppStatus: Equatable {
    case idle
    case loadingModel(String)
    case recording
    case transcribing
    case rewriting
    case error(String)

    var menuLabel: String {
        switch self {
        case .idle: return "Ready"
        case .loadingModel(let m): return "Loading \(m)…"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .rewriting: return "Rewriting…"
        case .error(let e): return "Error: \(e)"
        }
    }

    /// SF Symbol shown as the menu bar icon.
    var symbolName: String {
        switch self {
        case .idle: return "mic"
        case .loadingModel, .transcribing, .rewriting: return "arrow.triangle.2.circlepath"  // spins while busy
        case .recording: return "mic.fill"
        case .error: return "exclamationmark.triangle"
        }
    }
}

/// A user-facing error surfaced in the menu bar (and as a transient HUD/status).
/// Carries a short headline plus an optional recovery hint so the UI can render
/// something actionable (e.g. "enable it in System Settings").
struct AppError: Equatable {
    var message: String
    var hint: String?

    init(_ message: String, hint: String? = nil) {
        self.message = message
        self.hint = hint
    }

    /// Single line suitable for compact display.
    var displayText: String {
        if let hint, !hint.isEmpty { return "\(message) — \(hint)" }
        return message
    }
}

/// Central observable state shared across the app. Lives on the main actor.
@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var lastTranscript: String = ""
    /// Live caption for realtime mode: confirmed (locked) + hypothesis (tentative).
    @Published var liveConfirmed: String = ""
    @Published var liveHypothesis: String = ""
    /// Non-fatal warning shown in the menu (e.g. rewrite fell back to raw text).
    @Published var lastWarning: String?
    /// User-facing error surfaced in the menu bar dropdown. Cleared on the next
    /// successful action (or automatically after a short delay).
    @Published var lastError: AppError?
    /// Continuously-updated angle for the menu bar spinner (driven by a timer so
    /// it actually animates in the status bar, where SwiftUI animations don't tick).
    @Published var spinnerAngle: Double = 0

    private var spinTimer: Timer?
    private var errorClearWorkItem: DispatchWorkItem?

    var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    var isBusy: Bool {
        switch status {
        case .transcribing, .rewriting, .loadingModel: return true
        default: return false
        }
    }

    func setStatus(_ s: AppStatus) {
        status = s
        updateSpinner()
    }

    /// Surfaces a user-visible error: sets the menu-bar status, the dropdown
    /// banner, and (after a delay) auto-clears the banner so it doesn't linger.
    func setError(_ error: AppError) {
        lastError = error
        setStatus(.error(error.message))
        scheduleErrorClear()
    }

    func clearError() {
        errorClearWorkItem?.cancel()
        errorClearWorkItem = nil
        lastError = nil
        if case .error = status { setStatus(.idle) }
    }

    private func scheduleErrorClear() {
        errorClearWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastError = nil
            if case .error = self.status { self.setStatus(.idle) }
        }
        errorClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func updateSpinner() {
        if isBusy {
            guard spinTimer == nil else { return }
            spinTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.spinnerAngle = (self.spinnerAngle + 18).truncatingRemainder(dividingBy: 360)
                }
            }
        } else {
            spinTimer?.invalidate()
            spinTimer = nil
            spinnerAngle = 0
        }
    }

    func clearLive() {
        liveConfirmed = ""
        liveHypothesis = ""
    }
}
