import SwiftUI
import AppKit

/// The menu bar icon: the Looped brand mark.
///
/// Every state is rendered through the same pipeline at one fixed size (so the
/// icon never changes size between states). Idle is a **template** image (adapts
/// to light/dark); active states are **non-template** colored bitmaps, because
/// MenuBarExtra flattens plain SwiftUI labels to a monochrome template and would
/// otherwise strip the color.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        Image(nsImage: Self.icon(for: state.status))
            .accessibilityLabel("Looped Whisper — \(state.status.menuLabel)")
    }

    private static func icon(for status: AppStatus) -> NSImage {
        switch status {
        case .idle:
            return badge(key: "idle", background: nil, glyph: .black, template: true)
        case .recording:
            return badge(key: "rec", background: BrandColor.recording, glyph: .white, template: false)
        case .transcribing, .rewriting, .loadingModel:
            return badge(key: "busy", background: BrandColor.transcribing, glyph: .white, template: false)
        case .error:
            return badge(key: "err", background: BrandColor.error, glyph: .white, template: false)
        }
    }

    // MARK: - rendering

    private static let canvas = CGSize(width: 26, height: 18)
    private static let glyphSize: CGFloat = 16
    private static var cache: [String: NSImage] = [:]

    private static func badge(key: String, background: Color?, glyph: Color, template: Bool) -> NSImage {
        if let cached = cache[key] { return cached }
        let view = ZStack {
            if let background {
                Capsule(style: .continuous).fill(background)   // pill, like the macOS mic indicator
            }
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(glyph)
                .frame(width: glyphSize, height: glyphSize)
        }
        .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = template
        cache[key] = image
        return image
    }
}
