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
    /// Continuously-updated angle for the menu bar spinner (driven by a timer so
    /// it actually animates in the status bar, where SwiftUI animations don't tick).
    @Published var spinnerAngle: Double = 0

    private var spinTimer: Timer?

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
