import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Hold to record (down → start, up → stop + transcribe).
    static let pushToTalk = Self("pushToTalk")
    /// Press to toggle recording on/off.
    static let toggleRecording = Self("toggleRecording")
    /// Hold to rewrite the current selection: copy it, speak an instruction,
    /// paste the rewrite back in place on release.
    static let rewriteSelection = Self("rewriteSelection")
    /// Press to paste the most recent dictation again, wherever the cursor is.
    static let pasteLastDictation = Self("pasteLastDictation")
}

/// Binds the standard modifier-combo global shortcuts to the coordinator.
/// (The fn/Globe key is handled separately by `FnKeyMonitor`, since fn cannot
/// be registered through the Carbon hotkey API this package uses.)
@MainActor
final class HotkeyManager {
    private weak var coordinator: Coordinator?

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    /// The shortcuts the app ships with. They use Carbon hotkeys and need no
    /// permissions.
    static let defaults: [(name: KeyboardShortcuts.Name, shortcut: KeyboardShortcuts.Shortcut)] = [
        (.pushToTalk,         .init(.space, modifiers: [.control, .option])),   // ⌃⌥Space, hold
        (.toggleRecording,    .init(.d, modifiers: [.control, .option])),       // ⌃⌥D
        (.rewriteSelection,   .init(.r, modifiers: [.control, .option])),       // ⌃⌥R, hold
        (.pasteLastDictation, .init(.v, modifiers: [.control, .option])),       // ⌃⌥V
    ]

    /// Gives any shortcut that has none its default: on first launch, and for
    /// a shortcut added by an update.
    static func installDefaultShortcutsIfNeeded() {
        for item in defaults where KeyboardShortcuts.getShortcut(for: item.name) == nil {
            KeyboardShortcuts.setShortcut(item.shortcut, for: item.name)
        }
    }

    /// Puts every shortcut back to its default, replacing the user's own.
    static func resetShortcutsToDefaults() {
        for item in defaults { KeyboardShortcuts.setShortcut(item.shortcut, for: item.name) }
    }

    func register() {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.coordinator?.beginRecording()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            // Ends whichever pipeline the key-down started: with the smart
            // hotkey on, this same key may have begun a selection rewrite.
            self?.coordinator?.endHeldRecording()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in
            self?.coordinator?.toggleRecording()
        }
        // Hold to speak the instruction, release to rewrite — the same
        // push-to-talk shape as dictation, so the two feel alike.
        KeyboardShortcuts.onKeyDown(for: .rewriteSelection) { [weak self] in
            self?.coordinator?.beginSelectionRewrite()
        }
        KeyboardShortcuts.onKeyUp(for: .rewriteSelection) { [weak self] in
            self?.coordinator?.endSelectionRewrite()
        }
        KeyboardShortcuts.onKeyUp(for: .pasteLastDictation) { [weak self] in
            self?.coordinator?.pasteLastDictation()
        }
    }
}
