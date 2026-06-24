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
        preview(name)
    }

    /// Plays a named system sound immediately (used by the settings preview button).
    static func preview(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
