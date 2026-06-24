import AppKit
import AVFoundation
import ApplicationServices

/// Tracks and requests the three permissions the app needs:
/// - Microphone (recording)
/// - Accessibility (synthesizing Cmd+V paste, and an active fn event tap)
/// - Input Monitoring (observing the fn/Globe key via a CGEventTap)
@MainActor
final class PermissionsManager: ObservableObject {
    @Published var microphoneAuthorized = false
    @Published var accessibilityTrusted = false
    @Published var inputMonitoringGranted = false

    private var pollTimer: Timer?

    func refresh() {
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityTrusted = AXIsProcessTrusted()
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Grants happen in System Settings (out of process), so poll while the
    /// Permissions UI is visible and whenever the app is reactivated.
    func startMonitoring() {
        refresh()
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appBecameActive() { refresh() }

    /// Clears this app's TCC grants (equivalent to `tccutil reset … <bundle id>`)
    /// then relaunches, so the user can re-grant from a clean slate. Useful when a
    /// toggle won't stick due to stale entries from earlier builds.
    func resetAndRelaunch() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.looped.whisper"
        for service in ["Accessibility", "ListenEvent", "Microphone"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            try? process.run()
            process.waitUntilExit()
        }
        quitAndRelaunch()
    }

    /// Accessibility & Input Monitoring grants only take effect in a fresh
    /// process — quit and relaunch so the event tap / paste actually work.
    func quitAndRelaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.8; open \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Triggers the system Accessibility prompt (shown once per launch).
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    // Deep links into the relevant System Settings panes.
    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
    func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }
    func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
