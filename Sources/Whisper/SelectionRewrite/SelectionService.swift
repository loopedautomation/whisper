import AppKit

/// Reads and replaces the selection in whatever app the user is in.
///
/// Nothing portable can read another application's selection directly, so the
/// only route that works everywhere is: press ⌘C, read the clipboard, rewrite,
/// write the clipboard, press ⌘V. That means **the user's clipboard ends up
/// holding the rewrite** — an unavoidable consequence of this approach, and one
/// the UI states plainly rather than hiding.
///
/// Requires Accessibility, like every other synthesized keystroke in the app.
@MainActor
enum SelectionService {

    enum SelectionError: LocalizedError {
        case nothingSelected
        case notText

        var errorDescription: String? {
            switch self {
            case .nothingSelected: return "No text selected"
            case .notText: return "The selection isn't text"
            }
        }

        var hint: String {
            switch self {
            case .nothingSelected: return "select some text first, then press the shortcut"
            case .notText: return "select plain text and try again"
            }
        }
    }

    /// How long to wait for the target app to service the copy. Generous enough
    /// for a slow or busy app, short enough that "nothing was selected" is
    /// reported quickly rather than looking like a hang.
    private static let copyTimeout: Duration = .milliseconds(1200)
    private static let pollInterval: Duration = .milliseconds(25)

    /// Copies the current selection and returns it.
    ///
    /// Detection is by pasteboard `changeCount`, not by comparing strings: if
    /// the user's selection happens to equal what is already on the clipboard,
    /// a string comparison would read as "nothing happened". An unchanged
    /// count after the timeout means ⌘C was a no-op — nothing was selected.
    static func capture(targetApp: NSRunningApplication?) async throws -> String {
        let pasteboard = NSPasteboard.general

        activate(targetApp)
        // Let the activation land before the keystroke, or the copy goes to
        // whatever was frontmost a moment ago.
        try? await Task.sleep(for: .milliseconds(120))
        // Read the change count as late as possible. Anything else that writes
        // the pasteboard in the meantime — clipboard managers are the usual
        // culprit — looks exactly like a successful copy, which would turn a
        // no-op ⌘C into "here is your selection" using stale clipboard content.
        let before = pasteboard.changeCount
        TextInserter.copy()

        var waited = Duration.zero
        while waited < copyTimeout {
            try? await Task.sleep(for: pollInterval)
            waited += pollInterval
            guard pasteboard.changeCount != before else { continue }
            guard let text = pasteboard.string(forType: .string) else {
                throw SelectionError.notText
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SelectionError.nothingSelected
            }
            return text
        }
        throw SelectionError.nothingSelected
    }

    /// Puts `text` on the clipboard and pastes it over the selection.
    static func replaceSelection(with text: String, targetApp: NSRunningApplication?) {
        // No clipboard restore here: the paste has to read from the clipboard,
        // and restoring afterwards races the target app's own read.
        TextInserter.insert(text, restoreClipboard: false, targetApp: targetApp)
    }

    private static func activate(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated, !app.isActive else { return }
        app.activate()
    }
}
