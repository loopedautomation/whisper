import AppKit
import SwiftUI

/// A floating, always-on-top, non-activating panel that hosts the live-caption
/// view in the top-right corner of the active screen. Used for realtime mode.
@MainActor
final class HUDPanelController {
    private var panel: NSPanel?
    private let state: AppState

    private let size = NSSize(width: 380, height: 150)
    private let margin: CGFloat = 16

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if panel == nil { panel = makePanel() }
        reposition()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating                       // always on top
        panel.isOpaque = false
        panel.backgroundColor = .clear                // let the glass show through
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let host = NSHostingView(rootView: LiveCaptionView(state: state))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    /// Places the panel in the top-right of the screen with the menu bar's active screen preferred.
    private func reposition() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
