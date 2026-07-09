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

        var appValue: CFTypeRef?
        let appErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &appValue)
        switch appErr {
        case .success:
            // The frontmost app must also have a focused window: after the
            // user closes their last window the app can stay frontmost with
            // nowhere for a paste to go.
            let app = appValue as! AXUIElement
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
        let err = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        switch err {
        case .success:
            guard let value else { return .noFocus }
            return isEditable(value as! AXUIElement) ? .editable : .unknown
        case .noValue:
            return .noFocus
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
