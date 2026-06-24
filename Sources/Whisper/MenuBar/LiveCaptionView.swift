import SwiftUI

/// Floating live-caption content for realtime mode, rendered on liquid glass.
/// Confirmed text is solid; the tentative hypothesis is greyed.
struct LiveCaptionView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: state.status.symbolName)
                    .rotationEffect(.degrees(state.isBusy ? state.spinnerAngle : 0))
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
