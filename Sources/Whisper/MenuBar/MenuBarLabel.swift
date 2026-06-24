import SwiftUI

/// The menu bar icon: the Looped brand mark (a vector template image from the
/// asset catalog, so it stays crisp and adapts to light/dark). The pill behind
/// it tints by state — orange while recording, amber while busy — so a single
/// asset covers every state.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .frame(width: 22, height: 18)
            .background {
                if let color = backgroundColor {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color)
                        .opacity(backgroundOpacity)
                }
            }
            .accessibilityLabel("Looped Whisper — \(state.status.menuLabel)")
    }

    /// macOS's system recording-indicator orange.
    private static let recordingOrange = Color(.sRGB, red: 1.0, green: 0x92 / 255.0, blue: 0x30 / 255.0)

    private var backgroundColor: Color? {
        switch state.status {
        case .recording:                                return Self.recordingOrange
        case .transcribing, .rewriting, .loadingModel:  return .yellow
        case .error:                                    return .red
        case .idle:                                     return nil   // no background
        }
    }

    /// Gently pulse the background while busy (timer-driven `spinnerAngle`
    /// re-renders the label; menu bar SwiftUI animations don't tick on their own).
    private var backgroundOpacity: Double {
        guard state.isBusy else { return 1 }
        let radians = state.spinnerAngle * .pi / 180
        return 0.45 + 0.55 * abs(sin(radians))
    }
}
