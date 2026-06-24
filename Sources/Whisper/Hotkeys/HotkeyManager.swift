import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Hold to record (down → start, up → stop + transcribe).
    static let pushToTalk = Self("pushToTalk")
    /// Press to toggle recording on/off.
    static let toggleRecording = Self("toggleRecording")
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

    /// Ships sensible default global shortcuts on first launch (only if the user
    /// hasn't set their own). These use Carbon hotkeys and need no permissions.
    ///   • Push to talk (hold):  ⌃⌥Space
    ///   • Toggle recording:     ⌃⌥R
    static func installDefaultShortcutsIfNeeded() {
        if KeyboardShortcuts.getShortcut(for: .pushToTalk) == nil {
            KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.control, .option]), for: .pushToTalk)
        }
        if KeyboardShortcuts.getShortcut(for: .toggleRecording) == nil {
            KeyboardShortcuts.setShortcut(.init(.r, modifiers: [.control, .option]), for: .toggleRecording)
        }
    }

    func register() {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.coordinator?.beginRecording()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.coordinator?.endRecording()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in
            self?.coordinator?.toggleRecording()
        }
    }
}
