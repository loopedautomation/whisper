import AppKit
import Carbon.HIToolbox

/// Inserts text at the user's cursor by placing it on the clipboard and
/// synthesizing a Cmd+V keystroke. Requires Accessibility permission to post
/// events into other applications.
enum TextInserter {
    enum DeliveryResult {
        case pasted
        /// Nothing had keyboard focus, so no paste was attempted; the text is
        /// left on the clipboard for the user to paste manually.
        case copiedOnly
    }

    /// Re-activates `app` if it isn't already frontmost, so a keystroke sent
    /// right after reliably lands there instead of wherever focus drifted to
    /// while transcription (and any optional detection/rewrite) was running.
    private static func refocus(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated, !app.isActive else { return }
        app.activate()
    }

    /// Copies `text` to the clipboard and pastes it at the cursor.
    /// If `restoreClipboard` is true, the prior clipboard contents are restored
    /// after the paste completes. `targetApp`, if given, is re-activated first.
    /// `completion` runs on the main queue with what actually happened.
    static func insert(_ text: String, restoreClipboard: Bool, targetApp: NSRunningApplication? = nil,
                       completion: @escaping (DeliveryResult) -> Void = { _ in }) {
        let previous = restoreClipboard ? ClipboardService.currentString() : nil
        ClipboardService.set(text)
        refocus(targetApp)
        waitForActivation(of: targetApp) {
            switch FocusInspector.focusStatus() {
            case .noFocus:
                // A Cmd+V here would land nowhere and — with restore on —
                // the transcript would then be wiped from the clipboard too.
                // Keep it on the clipboard instead and let the caller warn.
                completion(.copiedOnly)
            case .editable:
                paste()
                if restoreClipboard {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        ClipboardService.restore(previous)
                    }
                }
                completion(.pasted)
            case .unknown:
                // Focus exists but we can't confirm it takes text (opaque AX
                // trees, e.g. some Electron apps). Attempt the paste, but skip
                // the clipboard restore so the transcript stays recoverable
                // if the paste silently no-ops.
                paste()
                completion(.pasted)
            }
        }
    }

    /// Waits the usual pasteboard settle time, then keeps polling briefly if
    /// the target app hasn't finished activating yet (a fixed delay races
    /// against slow app switches — the old cause of pastes landing nowhere).
    private static func waitForActivation(of app: NSRunningApplication?, attempts: Int = 6,
                                          then block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let app, !app.isTerminated, !app.isActive, attempts > 0 {
                waitForActivation(of: app, attempts: attempts - 1, then: block)
            } else {
                block()
            }
        }
    }

    /// Types `text` at the cursor as synthesized Unicode keystrokes (no clipboard).
    /// Used for incremental/live insertion so we don't clobber the pasteboard
    /// on every chunk. Requires Accessibility, like `paste()`. `targetApp`, if
    /// given, is re-activated first (a no-op when it's already frontmost).
    static func typeString(_ text: String, targetApp: NSRunningApplication? = nil) {
        guard !text.isEmpty else { return }
        refocus(targetApp)
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
