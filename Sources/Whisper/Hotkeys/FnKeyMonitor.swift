import AppKit
import Carbon.HIToolbox

/// Observes the physical fn/Globe key via a passive CGEventTap and reports
/// "hold" (push-to-talk) and "double-tap" gestures.
///
/// Notes:
/// - We filter on the physical key code (kVK_Function == 63) on flagsChanged,
///   NOT the `.function` modifier flag, which also fires for arrow/F/nav keys.
/// - The tap is *passive* (listenOnly) so it never consumes fn — system
///   Dictation still works; we just observe alongside it.
/// - Passive observation requires Input Monitoring permission.
@MainActor
final class FnKeyMonitor {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    /// fn was held and then another key was pressed: the user wanted fn+arrow
    /// or fn+delete, not a dictation. Whatever `onDown` started should be
    /// dropped; `onUp` does not follow.
    var onInterrupted: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var isDown = false
    private var interrupted = false
    private var downAt: CFAbsoluteTime = 0
    /// Key codes the keyboard sends as part of pressing fn itself, learned
    /// per hold: anything that arrives in the same instant as the press.
    private var ownKeyCodes: Set<Int64> = []
    /// A second key pressed by a person lands later than this after fn.
    private let chordGrace: CFTimeInterval = 0.06
    private var lastTapTime: CFAbsoluteTime = 0
    private let doubleTapWindow: CFTimeInterval = 0.35

    private let fnKeyCode: Int64 = Int64(kVK_Function)
    /// Some keyboards and remappers (Karabiner) send the Globe key as this key
    /// code alongside the fn flag. It is the same key, not a second one.
    private let globeKeyCode: Int64 = 179

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                switch type {
                case .flagsChanged, .keyDown:
                    monitor.handle(type: type, event: event)
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    // The system switches a tap off when it is slow to answer.
                    // No more events arrive after that, so this is the one
                    // place to turn it back on.
                    monitor.reenable()
                default:
                    break
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            NSLog("FnKeyMonitor: failed to create event tap (Input Monitoring permission?)")
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Belt and braces: a tap can also be disabled without either
        // notification, and then the key silently stops working.
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let tap = self?.tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isDown = false
        interrupted = false
    }

    private nonisolated func reenable() {
        Task { @MainActor in
            if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
    }

    private nonisolated func handle(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let fnActive = event.flags.contains(.maskSecondaryFn)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        Task { @MainActor in
            if type == .keyDown {
                // Another key while fn is held makes this a key combination.
                guard self.isDown, !self.interrupted,
                      keyCode != self.fnKeyCode, keyCode != self.globeKeyCode else { return }
                // Some keyboards send a key-down of their own with the fn
                // press, and repeat it while fn is held. That is still fn.
                if CFAbsoluteTimeGetCurrent() - self.downAt < self.chordGrace {
                    self.ownKeyCodes.insert(keyCode)
                    DevLog.write("fn: key \(keyCode) arrived with the press, ignored")
                    return
                }
                guard !isRepeat, !self.ownKeyCodes.contains(keyCode) else { return }
                DevLog.write("fn: interrupted by key \(keyCode)")
                self.interrupted = true
                self.lastTapTime = 0
                self.onInterrupted?()
                return
            }
            guard keyCode == self.fnKeyCode else { return }

            if fnActive && !self.isDown {
                self.isDown = true
                self.interrupted = false
                self.downAt = CFAbsoluteTimeGetCurrent()
                self.ownKeyCodes = []
                DevLog.write("fn: down")
                self.onDown?()
            } else if !fnActive && self.isDown {
                self.isDown = false
                DevLog.write("fn: up after \(Int((CFAbsoluteTimeGetCurrent() - self.downAt) * 1000)) ms, interrupted=\(self.interrupted)")
                // After a combination, nothing fires until fn is pressed afresh.
                guard !self.interrupted else { self.interrupted = false; return }
                self.onUp?()
                let now = CFAbsoluteTimeGetCurrent()
                if now - self.lastTapTime <= self.doubleTapWindow {
                    self.onDoubleTap?()
                    self.lastTapTime = 0
                } else {
                    self.lastTapTime = now
                }
            }
        }
    }
}
