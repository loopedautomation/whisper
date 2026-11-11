import AppKit
import ApplicationServices
import SwiftUI

/// A small panel that sits on the System Settings window with the app as a
/// draggable tile, so granting a permission is one drag into the list above
/// instead of hunting for the app behind the "+" button.
///
/// Accessibility and Input Monitoring both take an app dropped onto their
/// list. Microphone is a switch, not a list you add to, so it has no guide.
@MainActor
final class PermissionGuide {
    enum Permission {
        case accessibility, inputMonitoring

        var pane: String {
            switch self {
            case .accessibility:   return "Privacy_Accessibility"
            case .inputMonitoring: return "Privacy_ListenEvent"
            }
        }

        var isGranted: Bool {
            switch self {
            case .accessibility:
                return AXIsProcessTrusted()
            case .inputMonitoring:
                return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            }
        }
    }

    static let shared = PermissionGuide()

    private var panel: NSPanel?
    private var timer: Timer?
    private var permission: Permission = .accessibility
    private var sawSettings = false
    private var shownAt = Date()

    /// Give up if System Settings never appears.
    private static let patience: TimeInterval = 20
    private static let size = NSSize(width: 440, height: 112)

    /// Opens the permission's pane in System Settings and shows the guide on it.
    func show(_ permission: Permission) {
        close()
        self.permission = permission
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.pane)") {
            NSWorkspace.shared.open(url)
        }
        guard !permission.isGranted else { return }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = PermissionGuideContent(frame: NSRect(origin: .zero, size: Self.size))
        self.panel = panel

        sawSettings = false
        shownAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func tick() {
        guard let panel else { return }
        if permission.isGranted { close(); return }

        guard let settings = Self.settingsWindowFrame() else {
            // Closed (or never opened): nothing left to point at.
            if sawSettings || Date().timeIntervalSince(shownAt) > Self.patience { close() }
            return
        }
        sawSettings = true

        // Bottom-right corner of the Settings window, kept on its screen.
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? settings
        var x = settings.maxX - Self.size.width - 16
        var y = settings.minY + 16
        x = min(max(x, visible.minX + 8), visible.maxX - Self.size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - Self.size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    /// The System Settings window's frame in AppKit coordinates, if it is on
    /// screen. Window bounds and owner are readable without any permission.
    private static func settingsWindowFrame() -> NSRect? {
        guard let settings = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let frames = windows.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == settings.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 300, rect.height > 300 else { return nil }
            return rect
        }
        guard let quartz = frames.max(by: { $0.width * $0.height < $1.width * $1.height }),
              let primary = NSScreen.screens.first else { return nil }
        // Quartz measures from the top of the primary display, AppKit from its bottom.
        return NSRect(x: quartz.minX, y: primary.frame.height - quartz.maxY,
                      width: quartz.width, height: quartz.height)
    }
}

/// The panel's content: the instruction, and the app as a tile to drag.
private final class PermissionGuideContent: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        let name = PermissionAppTile.appName
        let label = NSTextField(labelWithString: "↑  Drag \(name) into the list above")
        label.font = PermissionAppTile.sans(13, weight: 500)
        label.frame = NSRect(x: 16, y: frame.height - 38, width: frame.width - 32, height: 20)
        label.identifier = NSUserInterfaceItemIdentifier("instruction")
        addSubview(label)

        addSubview(PermissionAppTile(frame: NSRect(x: 16, y: 14, width: frame.width - 32, height: 48)))
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor(Looped.raised).cgColor
            layer?.borderColor = NSColor(Looped.ruleStrong).cgColor
        }
        for case let label as NSTextField in subviews { label.textColor = NSColor(Looped.ink) }
    }
}

/// The app's icon and name, draggable as the app bundle itself: dropping it
/// on a Privacy & Security list adds the app to that list.
private final class PermissionAppTile: NSView, NSDraggingSource {
    /// The name System Settings will list the app under.
    static var appName: String {
        let name = FileManager.default.displayName(atPath: Bundle.main.bundlePath)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Work Sans at a weight, as an AppKit font; the system font without it.
    static func sans(_ size: CGFloat, weight: CGFloat) -> NSFont {
        _ = LoopedType.registered
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "Work Sans",
            .variation: [NSNumber(value: 0x7767_6874): weight],   // 'wght'
        ])
        if let font = NSFont(descriptor: descriptor, size: size), font.familyName == "Work Sans" { return font }
        return .systemFont(ofSize: size, weight: weight >= 500 ? .medium : .regular)
    }

    private let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    private var mouseDown: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(Looped.shade).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        icon.draw(in: NSRect(x: 10, y: (bounds.height - 32) / 2, width: 32, height: 32))
        let name = Self.appName as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.sans(13, weight: 400),
            .foregroundColor: NSColor(Looped.ink),
        ]
        let height = name.size(withAttributes: attributes).height
        name.draw(at: NSPoint(x: 52, y: (bounds.height - height) / 2), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) { mouseDown = event }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDown else { return }
        mouseDown = nil
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        let snapshot = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            snapshot.addRepresentation(rep)
        }
        item.setDraggingFrame(bounds, contents: snapshot)
        beginDraggingSession(with: [item], event: start, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
