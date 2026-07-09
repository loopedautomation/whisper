import SwiftUI

/// Floating live-caption content for realtime mode, rendered on liquid glass.
/// Confirmed text is solid; the tentative hypothesis is greyed.
struct LiveCaptionView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusGlyph(symbolName: state.status.symbolName, spinning: state.isBusy)
                Text(state.status.menuLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                (Text(state.liveConfirmed.isEmpty ? "" : state.liveConfirmed + " ")
                    .foregroundStyle(.primary)
                 + Text(state.liveHypothesis)
                    .foregroundStyle(.secondary))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(GlassPanelBackground())
    }
}

/// Status symbol that spins while busy. The rotation is a local repeating
/// SwiftUI animation — no published state churn, so other AppState observers
/// (like the menu bar label) don't re-render on every frame.
private struct StatusGlyph: View {
    let symbolName: String
    let spinning: Bool
    @State private var angle = 0.0

    var body: some View {
        Image(systemName: symbolName)
            .rotationEffect(.degrees(angle))
            .onAppear { if spinning { spin() } }
            .onChange(of: spinning) { _, now in
                if now {
                    spin()
                } else {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { angle = 0 }
                }
            }
    }

    private func spin() {
        angle = 0
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { angle = 360 }
    }
}

/// Liquid Glass background on macOS 26+, with a material fallback for older systems.
private struct GlassPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.12)))
        }
    }
}
