import AppKit
import ApplicationServices
import os

/// Inspects, via the Accessibility API, whether the user actually has
/// somewhere for pasted/typed text to land. Requires the same Accessibility
/// trust the paste itself needs, so this adds no new permission.
///
/// Bias: fail open. A paste into nowhere is a minor annoyance; refusing to
/// paste when the cursor IS in a text box loses the transcript. `.noFocus`
/// is only returned when the frontmost app's AX tree is demonstrably alive
/// AND it positively reports that nothing has focus.
///
/// Notably, the system-wide kAXFocusedApplicationAttribute is NOT used:
/// Electron apps (Discord, Claude, …) don't participate in the AX focus
/// chain until their tree is enabled, so that query answers "no focused
/// application" even while the user's cursor sits in a text box. The
/// frontmost app comes from NSWorkspace instead, which always knows.
enum FocusInspector {
    private static let log = Logger(subsystem: "com.looped.whisper", category: "focus")

    enum Status {
        /// A focused UI element that is clearly text-editable.
        case editable
        /// Can't confirm where focus is (opaque or disabled AX trees, e.g.
        /// Electron apps). Treated permissively — a paste is still attempted.
        case unknown
        /// The AX tree is responsive and positively reports no focused
        /// window/element — a paste would be a silent no-op, so the caller
        /// should fall back to copy-only.
        case noFocus
    }

    static func focusStatus() -> Status {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            log.info("no frontmost application (NSWorkspace)")
            return .unknown
        }
        let app = AXUIElementCreateApplication(frontmost.processIdentifier)

        // Chromium/Electron keeps its AX tree disabled until an assistive
        // client asks. Ask before inspecting so the queries below have a
        // chance of answering truthfully. (The tree builds asynchronously,
        // so the very first dictation into such an app may still see an
        // empty tree — the fail-open rules below cover that.)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var element: CFTypeRef?
        let elErr = AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &element)
        var window: CFTypeRef?
        let winErr = AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &window)
        log.info("app=\(frontmost.bundleIdentifier ?? "?", privacy: .public) focusedUIElement err=\(elErr.rawValue, privacy: .public) focusedWindow err=\(winErr.rawValue, privacy: .public)")

        if elErr == .success, let element {
            return isEditable(element as! AXUIElement) ? .editable : .unknown
        }
        // No focused element was reported. Trust that as real no-focus only
        // when the tree is provably alive: the focused-window query must
        // also give a definite "none" (e.g. the frontmost app's last window
        // was closed). A dead/disabled tree errors out — paste anyway.
        if elErr == .noValue, winErr == .noValue {
            return .noFocus
        }
        return .unknown
    }

    /// The text currently selected in the frontmost app, read straight from the
    /// Accessibility API — or `nil` when that can't be determined.
    ///
    /// `nil` is not "nothing is selected": it means *unknown*, which is the
    /// answer for any app whose AX tree doesn't expose selection (Electron
    /// being the usual culprit). Callers must treat the two differently,
    /// because acting on "unknown" as though it were "empty" is how a rewrite
    /// turns into a dictation over the user's paragraph.
    ///
    /// Non-destructive, unlike the ⌘C probe: nothing touches the pasteboard.
    static func selectedText() -> String? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let app = AXUIElementCreateApplication(frontmost.processIdentifier)
        // Same wake-up as focusStatus: Chromium keeps its tree disabled until
        // an assistive client asks.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &element) == .success,
              let element else {
            log.info("selectedText: no focused element")
            return nil
        }

        var selection: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selection)
        guard err == .success, let text = selection as? String else {
            // `.noValue` here means the element has no selected-text attribute
            // at all — still unknown, not empty.
            log.info("selectedText: attribute unavailable (err=\(err.rawValue, privacy: .public))")
            return nil
        }
        return text
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String,
           ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) {
            return true
        }
        // Fallback for custom controls: a settable AXValue means it takes input.
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
            return settable.boolValue
        }
        return false
    }
}
