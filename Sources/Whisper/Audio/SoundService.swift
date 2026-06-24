import AppKit

/// Distinct moments in the capture lifecycle that can play a macOS system sound.
enum SoundEvent: String, CaseIterable, Identifiable {
    case start, stop, toggle, done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .start: return "Recording started"
        case .stop:  return "Recording stopped"
        case .toggle: return "Toggle recording"
        case .done:  return "Transcription ready"
        }
    }

    var enabledKey: String { "sound.\(rawValue).enabled" }
    var nameKey: String { "sound.\(rawValue).name" }

    var defaultSound: String {
        switch self {
        case .start: return "Pop"
        case .stop:  return "Bottle"
        case .toggle: return "Tink"
        case .done:  return "Glass"
        }
    }
}

/// Plays macOS system sounds for capture events, gated by a master toggle and a
/// per-event toggle. All are configurable in the Sounds settings page.
enum SoundService {
    /// Built-in macOS system sounds (/System/Library/Sounds).
    static let available = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    static func play(_ event: SoundEvent) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: PrefKey.soundsEnabled),
              defaults.bool(forKey: event.enabledKey) else { return }
        let name = defaults.string(forKey: event.nameKey) ?? event.defaultSound
        play(name: name, volume: currentVolume)
    }

    /// Plays a named system sound immediately at a given volume (used by the
    /// settings preview button so the slider's effect is audible while dragging).
    static func preview(_ name: String, volume: Float? = nil) {
        play(name: name, volume: volume ?? currentVolume)
    }

    private static var currentVolume: Float {
        Float(UserDefaults.standard.double(forKey: PrefKey.soundVolume))
    }

    private static func play(name: String, volume: Float) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = max(0, min(1, volume))
        sound.play()
    }
}
