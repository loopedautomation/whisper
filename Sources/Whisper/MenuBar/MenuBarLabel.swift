import SwiftUI
import AppKit

/// The menu bar icon: the Looped brand mark.
///
/// Every state is rendered through the same pipeline at one fixed size (so the
/// icon never changes size between states). Idle is a **template** image (adapts
/// to light/dark); active states are **non-template** coloured bitmaps, because
/// MenuBarExtra flattens plain SwiftUI labels to a monochrome template and would
/// otherwise strip the color.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: Self.icon(for: state.status, dark: colorScheme == .dark))
            .accessibilityLabel("Looped Whisper — \(state.status.menuLabel)")
    }

    /// The image for a state, in the brand's Day or Night colours. Also drawn
    /// in Settings → Status, so the key there can never drift from what the
    /// menu bar shows.
    static func icon(for status: AppStatus, dark: Bool) -> NSImage {
        let suffix = dark ? "-night" : "-day"
        switch status {
        case .idle:
            return badge(key: "idle", canvas: idleCanvas, pill: nil, template: true)
        case .recording:
            return badge(key: "rec" + suffix, canvas: pillCanvas, pill: BrandColor.recording(dark: dark), template: false)
        case .transcribing, .loadingModel:
            return badge(key: "busy" + suffix, canvas: pillCanvas, pill: BrandColor.working(dark: dark), template: false)
        case .rewriting:
            return badge(key: "rewrite" + suffix, canvas: pillCanvas, pill: BrandColor.rewriting(dark: dark), template: false)
        case .error:
            return badge(key: "err" + suffix, canvas: pillCanvas, pill: BrandColor.error(dark: dark), template: false)
        }
    }

    // MARK: - rendering

    /// Glyph stays a fixed size in every state; only the background pill grows.
    private static let glyphSize: CGFloat = 17
    private static let idleCanvas = CGSize(width: 24, height: 22)   // tight, no background
    private static let pillCanvas = CGSize(width: 36, height: 22)   // full-size pill like macOS
    private static var cache: [String: NSImage] = [:]

    private static func badge(key: String, canvas: CGSize, pill: BrandColor.Pill?, template: Bool) -> NSImage {
        if let cached = cache[key] { return cached }
        let view = ZStack {
            if let pill {
                Capsule(style: .continuous).fill(pill.fill)   // pill, like the macOS mic indicator
            }
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(pill?.glyph ?? .black)
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
