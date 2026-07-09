import AppKit
import ApplicationServices

/// Inspects, via the Accessibility API, whether the user actually has
/// somewhere for pasted/typed text to land. Requires the same Accessibility
/// trust the paste itself needs, so this adds no new permission.
enum FocusInspector {
    enum Status {
        /// A focused UI element that is clearly text-editable.
        case editable
        /// Something is focused, but we can't tell whether it accepts text
        /// (common in Electron/web apps whose AX trees are opaque). Treated
        /// permissively — a paste is still attempted.
        case unknown
        /// No focused window or UI element at all — a paste would be a
        /// silent no-op, so the caller should fall back to copy-only.
        case noFocus
    }

    static func focusStatus() -> Status {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AXUIElement?
        var appValue: CFTypeRef?
        let appErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &appValue)
        switch appErr {
        case .success:
            // The frontmost app must also have a focused window: after the
            // user closes their last window the app can stay frontmost with
            // nowhere for a paste to go.
            let app = appValue as! AXUIElement
            focusedApp = app
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .noValue {
                return .noFocus
            }
        case .noValue, .apiDisabled:
            return appErr == .noValue ? .noFocus : .unknown
        default:
            break   // can't inspect; stay permissive
        }

        var value: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        if err == .noValue || (err == .success && value == nil), let app = focusedApp {
            // Electron apps keep their AX tree disabled until an assistive
            // client asks for it, so "no focused element" here can be a lie
            // even while the cursor sits in a text box (Discord, Claude, …).
            // Ask Chromium to enable it and re-query once.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            value = nil
            err = AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        }
        switch err {
        case .success where value != nil:
            return isEditable(value as! AXUIElement) ? .editable : .unknown
        case .success, .noValue:
            // There's a focused window but no reported focused element. For
            // native apps that means nothing has focus, but apps with absent
            // or lazily-built AX trees report this even with an active text
            // box — so attempt the paste rather than silently dropping it.
            return .unknown
        default:
            return .unknown
        }
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
