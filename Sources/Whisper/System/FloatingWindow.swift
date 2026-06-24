import SwiftUI
import AppKit

/// Sets the host window's level (e.g. `.floating`) so it stays above other apps.
private struct WindowLevelSetter: NSViewRepresentable {
    let level: NSWindow.Level

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        DispatchQueue.main.async { [weak view] in
            view?.window?.level = level
        }
    }
}

extension View {
    /// Keeps the enclosing window above normal windows of other apps.
    func floatingWindow(_ level: NSWindow.Level = .floating) -> some View {
        background(WindowLevelSetter(level: level))
    }
}
