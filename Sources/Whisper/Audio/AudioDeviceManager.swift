import Foundation
import CoreAudio
import Combine

/// Observable list of available audio input devices plus the persisted selection.
/// Refreshes automatically when devices appear or disappear, or when the system
/// default input changes (so the "System Default" label tracks the OS).
@MainActor
final class AudioDeviceManager: ObservableObject {
    /// Available input devices (excludes the "System Default" pseudo-entry).
    @Published private(set) var devices: [AudioInputDevice] = []
    /// Persisted selection: a device UID, or `AudioInputDevices.systemDefaultUID` ("")
    /// to follow the macOS system default.
    @Published var selectedUID: String {
        didSet {
            guard selectedUID != oldValue else { return }
            UserDefaults.standard.set(selectedUID, forKey: PrefKey.inputDeviceUID)
        }
    }

    private var listenersInstalled = false

    init() {
        selectedUID = UserDefaults.standard.string(forKey: PrefKey.inputDeviceUID)
            ?? AudioInputDevices.systemDefaultUID
        refresh()
        installListeners()
    }

    deinit {
        // Listeners are tied to the system object's lifetime; the process owns this
        // manager for its whole lifetime, so no teardown is required in practice.
    }

    /// Re-enumerate devices and drop a stale selection back to System Default if its
    /// device is no longer present.
    func refresh() {
        devices = AudioInputDevices.all()
        if !selectedUID.isEmpty, !devices.contains(where: { $0.uid == selectedUID }) {
            selectedUID = AudioInputDevices.systemDefaultUID
        }
    }

    /// Human-readable name of the device currently driving capture.
    var selectedDisplayName: String {
        if selectedUID.isEmpty {
            if let id = AudioInputDevices.systemDefaultInputDeviceID(),
               let name = AudioInputDevices.all().first(where: { $0.deviceID == id })?.name {
                return "System Default (\(name))"
            }
            return "System Default"
        }
        return devices.first { $0.uid == selectedUID }?.name ?? "System Default"
    }

    // MARK: - Core Audio change notifications

    private func installListeners() {
        guard !listenersInstalled else { return }
        listenersInstalled = true

        for selector in [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
            ) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
}
