import Foundation

/// What a quick action does when its trigger phrase is spoken.
enum QuickActionKind: String, Codable, CaseIterable, Identifiable {
    case openURL            // open in the default browser (new tab)
    case openURLIncognito   // open in a private/incognito window
    case launchApp          // launch or activate a macOS app by name
    case quitApp            // quit a running macOS app by name
    case runShortcut        // run a Siri Shortcut by name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openURL: return "Open URL"
        case .openURLIncognito: return "Open URL (incognito)"
        case .launchApp: return "Open app"
        case .quitApp: return "Quit app"
        case .runShortcut: return "Run Shortcut"
        }
    }

    var symbolName: String {
        switch self {
        case .openURL: return "safari"
        case .openURLIncognito: return "eyeglasses"
        case .launchApp: return "app.badge"
        case .quitApp: return "xmark.app"
        case .runShortcut: return "square.stack.3d.up"
        }
    }

    /// Placeholder text for the target field in the editor.
    var targetHint: String {
        switch self {
        case .openURL, .openURLIncognito: return "https://example.com or https://google.com/search?q={{query}}"
        case .launchApp: return "App name, e.g. Slack"
        case .quitApp: return "App name, e.g. Slack"
        case .runShortcut: return "Shortcut name, e.g. Morning Routine"
        }
    }
}

/// A user-defined voice command: spoken trigger phrases mapped to an action.
/// `target` may contain `{{query}}`, filled with whatever the user said after
/// a prefix trigger ("search for cats" → query "cats").
struct QuickAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var triggers: [String]
    var kind: QuickActionKind
    var target: String
    var enabled = true
}

/// Local, offline trigger matching: exact or prefix match against the user's
/// trigger phrases after normalizing case/whitespace/trailing punctuation.
enum QuickActionMatcher {
    struct Match {
        var action: QuickAction
        /// Free text spoken after a prefix trigger, if any.
        var query: String?
    }

    /// Lowercase, collapse whitespace, strip leading/trailing punctuation —
    /// Whisper often appends a period and capitalizes the first word.
    static func normalize(_ text: String) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
        return trimmed.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Matches `transcript` against enabled actions. Exact trigger match wins;
    /// otherwise the longest prefix trigger (followed by a word break) wins and
    /// the remainder becomes the query. Returns nil when nothing matches — the
    /// transcript is ordinary dictation.
    static func match(_ transcript: String, actions: [QuickAction]) -> Match? {
        let text = normalize(transcript)
        guard !text.isEmpty else { return nil }

        var best: (match: Match, triggerLength: Int)?
        for action in actions where action.enabled {
            for trigger in action.triggers {
                let t = normalize(trigger)
                guard !t.isEmpty else { continue }
                if text == t {
                    // Exact match always wins.
                    return Match(action: action, query: nil)
                }
                if text.hasPrefix(t + " ") {
                    let query = String(text.dropFirst(t.count)).trimmingCharacters(in: .whitespaces)
                    // A prefix trigger with no target placeholder would silently
                    // drop the remainder — require the exact phrase instead.
                    guard action.target.contains("{{query}}"), !query.isEmpty else { continue }
                    if best == nil || t.count > best!.triggerLength {
                        best = (Match(action: action, query: query), t.count)
                    }
                }
            }
        }
        return best?.match
    }
}
