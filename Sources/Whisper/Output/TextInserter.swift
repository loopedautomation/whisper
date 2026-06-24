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

    /// Types `text` at the cursor as synthesized Unicode keystrokes (no clipboard).
    /// Used for incremental/live insertion so we don't clobber the pasteboard
    /// on every chunk. Requires Accessibility, like `paste()`.
    static func typeString(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        // Chunk to stay well under the event's UniChar buffer limit.
        for chunk in text.chunked(into: 20) {
            let utf16 = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            utf16.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
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

private extension String {
    func chunked(into size: Int) -> [Substring] {
        var result: [Substring] = []
        var idx = startIndex
        while idx < endIndex {
            let end = index(idx, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(self[idx..<end])
            idx = end
        }
        return result
    }
}
