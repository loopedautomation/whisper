import AppKit

/// Manages writing transcribed text to the general pasteboard, with optional
/// save/restore of the user's prior clipboard contents.
enum ClipboardService {
    /// Snapshot of the current pasteboard string (best-effort; only plain text).
    static func currentString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func set(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Restores a previously captured string (no-op if nil).
    static func restore(_ previous: String?) {
        guard let previous else { return }
        set(previous)
    }
}
