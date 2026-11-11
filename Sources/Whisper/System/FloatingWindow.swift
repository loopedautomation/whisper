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

/// Turns the host window's title bar into the ground for the Looped rail
/// header: no title, no chrome of its own, content drawn underneath it. An
/// empty unified toolbar makes the bar 52pt tall, the rail's height, so the
/// window controls sit centred in the rail.
private struct RailTitlebarSetter: NSViewRepresentable {
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
            guard let window = view?.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            if window.toolbar == nil {
                window.toolbar = NSToolbar()
            }
            window.toolbarStyle = .unified
        }
    }
}

extension View {
    /// Lets the view draw the Looped rail header under the window's title bar.
    func railTitlebar() -> some View {
        background(RailTitlebarSetter())
    }
}
