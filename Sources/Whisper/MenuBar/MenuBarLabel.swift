import SwiftUI

/// The menu bar icon. Spins while the app is busy (loading/transcribing/rewriting),
/// pulses while recording, and drives the floating live-caption HUD.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        // Timer-driven rotation (state.spinnerAngle) actually animates in the
        // status bar; SwiftUI's repeatForever animations don't tick there.
        Image(systemName: state.status.symbolName)
            .rotationEffect(.degrees(state.isBusy ? state.spinnerAngle : 0))
            .symbolEffect(.pulse, isActive: state.isRecording)
            .accessibilityLabel("Looped Whisper")
    }
}
