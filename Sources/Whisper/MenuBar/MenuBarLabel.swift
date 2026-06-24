import SwiftUI
import AppKit

/// The menu bar icon: the Looped brand mark.
///
/// - Idle: a vector **template** image (adapts to light/dark automatically).
/// - Active states: a pre-rendered **non-template** `NSImage` (a colored pill
///   with a white glyph) — MenuBarExtra renders plain SwiftUI labels as a
///   monochrome template and strips color, so colored states must be supplied
///   as a non-template bitmap instead.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let badge = activeBadge {
            Image(nsImage: badge)
                .accessibilityLabel("Looped Whisper — \(state.status.menuLabel)")
        } else {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .frame(width: 22, height: 18)
                .accessibilityLabel("Looped Whisper — \(state.status.menuLabel)")
        }
    }

    /// macOS's system recording-indicator orange.
    private static let recordingOrange = Color(.sRGB, red: 1.0, green: 0x92 / 255.0, blue: 0x30 / 255.0)

    private var activeBadge: NSImage? {
        switch state.status {
        case .recording:                                return Self.badge("rec", Self.recordingOrange)
        case .transcribing, .rewriting, .loadingModel:  return Self.badge("busy", .yellow)
        case .error:                                    return Self.badge("err", .red)
        case .idle:                                     return nil
        }
    }

    // MARK: - rendering

    private static var cache: [String: NSImage] = [:]

    private static func badge(_ key: String, _ color: Color) -> NSImage {
        if let cached = cache[key] { return cached }
        let view = ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color)
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
        }
        .frame(width: 22, height: 18)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = false   // keep the color
        cache[key] = image
        return image
    }
}
