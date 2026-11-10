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
    /// How long after the paste keystroke the previous clipboard comes back.
    static let restoreDelay: TimeInterval = 0.5

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
        let previous = restoreClipboard ? ClipboardService.snapshot() : nil
        let written = ClipboardService.set(text, transient: restoreClipboard)
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
                if let previous {
                    // Some apps read the clipboard a beat after the keystroke;
                    // restoring sooner makes them paste the old contents.
                    DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                        ClipboardService.restore(previous, expecting: written)
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

    /// `async` form of `waitForActivation`, for callers that need the app
    /// frontmost before synthesizing a keystroke of their own (the selection
    /// rewrite's ⌘C). Re-activates first, so callers don't repeat that too.
    static func awaitActivation(of app: NSRunningApplication?) async {
        refocus(app)
        await withCheckedContinuation { continuation in
            waitForActivation(of: app) { continuation.resume() }
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

    /// Synthesizes Cmd+V into the frontmost app.
    static func paste() {
        postCommandKey(CGKeyCode(kVK_ANSI_V))
    }

    /// Synthesizes Cmd+C into the frontmost app. Used to lift the selection out
    /// of another application, which is the only portable way to read it.
    static func copy() {
        postCommandKey(CGKeyCode(kVK_ANSI_C))
    }

    private static func postCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
