import AppKit
import Carbon.HIToolbox

/// Inserts text at the user's cursor by placing it on the clipboard and
/// synthesizing a Cmd+V keystroke. Requires Accessibility permission to post
/// events into other applications.
enum TextInserter {
    /// Copies `text` to the clipboard and pastes it at the cursor.
    /// If `restoreClipboard` is true, the prior clipboard contents are restored
    /// after the paste completes.
    static func insert(_ text: String, restoreClipboard: Bool) {
        let previous = restoreClipboard ? ClipboardService.currentString() : nil
        ClipboardService.set(text)
        // Give the pasteboard a moment to settle before posting the paste.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            paste()
            if restoreClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    ClipboardService.restore(previous)
                }
            }
        }
    }

    /// Synthesizes Cmd+V into the frontmost app.
    static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
