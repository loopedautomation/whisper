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

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false
    private var lastTapTime: CFAbsoluteTime = 0
    private let doubleTapWindow: CFTimeInterval = 0.35

    private let fnKeyCode: Int64 = Int64(kVK_Function)

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if type == .flagsChanged, let refcon {
                    let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    monitor.handle(event: event)
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
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isDown = false
    }

    private nonisolated func handle(event: CGEvent) {
        // Re-enable if the system disabled the tap (timeout / user input).
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        Task { @MainActor in
            // Defensive re-enable.
            if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            guard keyCode == self.fnKeyCode else { return }

            let fnActive = event.flags.contains(.maskSecondaryFn)
            if fnActive && !self.isDown {
                self.isDown = true
                self.onDown?()
            } else if !fnActive && self.isDown {
                self.isDown = false
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
