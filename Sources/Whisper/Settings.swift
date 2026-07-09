import Foundation
import SwiftUI
import AppKit

/// Keys for `@AppStorage` / `UserDefaults`-backed preferences.
enum PrefKey {
    static let selectedModel = "selectedModel"
    static let transcriptionMode = "transcriptionMode"   // "batch" | "realtime"
    static let outputBehavior = "outputBehavior"          // "copyPaste" | "copyOnly"
    static let restoreClipboard = "restoreClipboard"
    static let realtimeInsertion = "realtimeInsertion"    // "incremental" | "onStop"
    static let fnEnabled = "fnEnabled"
    static let fnMode = "fnMode"                           // "holdPTT" | "doubleTapToggle"
    static let rewriteEnabled = "rewriteEnabled"
    static let rewriteProvider = "rewriteProvider"        // "anthropic" | "openaiCompatible"
    static let rewriteModel = "rewriteModel"
    static let rewriteBaseURL = "rewriteBaseURL"          // for openaiCompatible
    static let rewritePrompt = "rewritePrompt"            // user prompt template, uses {{input}}
    static let language = "language"                       // legacy single-language hint, "" = auto
    static let preferredLanguages = "preferredLanguages"   // comma-joined ISO codes; empty = auto-detect all
    static let languageRepairEnabled = "languageRepairEnabled"   // opt-in: AI-repair cross-language mixups (sends transcript to your Rewrite provider); off by default to stay fully local
    static let soundsEnabled = "soundsEnabled"            // master sound toggle
    static let inputDeviceUID = "inputDeviceUID"          // audio input device UID, "" = system default
    static let soundVolume = "soundVolume"                // 0.0...1.0
    static let quickActionsEnabled = "quickActionsEnabled"        // opt-in voice quick actions
    static let quickActionsLLMFallback = "quickActionsLLMFallback" // opt-in: AI intent detection when no trigger matches (sends transcript to your Rewrite provider)
    static let quickActionsModifier = "quickActionsModifier"      // modifier held at recording start to arm quick actions; "none" = always armed
}

/// Modifier key that must be held when recording starts for quick actions to
/// be considered — so ordinary dictation can never accidentally trigger an
/// action. Works with any recording shortcut, including fn/Globe (e.g. 🌐+⌘).
enum QuickActionModifier: String, CaseIterable, Identifiable {
    case none, command, option, control, shift
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Always active"
        case .command: return "⌘ Command"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        }
    }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .none: return []
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }
}

enum TranscriptionMode: String, CaseIterable, Identifiable {
    case batch, realtime
    var id: String { rawValue }
    var label: String { self == .batch ? "Batch (on stop)" : "Realtime (live)" }
}

enum OutputBehavior: String, CaseIterable, Identifiable {
    case copyPaste, copyOnly
    var id: String { rawValue }
    var label: String { self == .copyPaste ? "Copy & paste at cursor" : "Copy to clipboard only" }
}

enum RealtimeInsertion: String, CaseIterable, Identifiable {
    case incremental, onStop
    var id: String { rawValue }
    var label: String { self == .incremental ? "Insert confirmed text live" : "Paste once on stop" }
}

enum FnMode: String, CaseIterable, Identifiable {
    case holdPTT, doubleTapToggle
    var id: String { rawValue }
    var label: String { self == .holdPTT ? "Hold fn — push to talk" : "Double-tap fn — toggle" }
}

enum RewriteProvider: String, CaseIterable, Identifiable {
    case anthropic, openaiCompatible
    var id: String { rawValue }
    var label: String { self == .anthropic ? "Anthropic (Claude)" : "OpenAI-compatible" }
    /// Sensible default model per provider — fast, low-cost tiers suited to
    /// transcript cleanup.
    var defaultModel: String { self == .anthropic ? "claude-haiku-4-5-20251001" : "gpt-5.4-mini" }
}

/// A selectable transcription language. `code` is the ISO-639-1 hint passed to
/// WhisperKit (empty string = auto-detect). All multilingual Whisper models
/// support these; the list is a curated set of the most widely spoken languages
/// and is trivial to extend — Whisper recognizes ~99 languages in total.
struct WhisperLanguage: Identifiable, Hashable {
    let code: String   // "" = auto-detect
    let label: String
    var id: String { code }

    static let known: [WhisperLanguage] = [
        .init(code: "",   label: "Auto-detect"),
        .init(code: "en", label: "English"),
        .init(code: "de", label: "German"),
        .init(code: "es", label: "Spanish"),
        .init(code: "fr", label: "French"),
        .init(code: "it", label: "Italian"),
        .init(code: "pt", label: "Portuguese"),
        .init(code: "nl", label: "Dutch"),
        .init(code: "ru", label: "Russian"),
        .init(code: "pl", label: "Polish"),
        .init(code: "uk", label: "Ukrainian"),
        .init(code: "tr", label: "Turkish"),
        .init(code: "ar", label: "Arabic"),
        .init(code: "hi", label: "Hindi"),
        .init(code: "zh", label: "Chinese"),
        .init(code: "ja", label: "Japanese"),
        .init(code: "ko", label: "Korean"),
        .init(code: "sv", label: "Swedish"),
        .init(code: "id", label: "Indonesian")
    ]

    /// Falls back to auto-detect for any stored code not in the list.
    static func label(for code: String) -> String {
        known.first { $0.code == code }?.label ?? "Auto-detect"
    }

    /// Decodes the comma-joined `preferredLanguages` pref into a set of codes.
    static func codes(from stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    /// Encodes a set of codes back into the stored comma-joined form. Order
    /// follows `known` so the value is stable.
    static func string(from codes: Set<String>) -> String {
        known.map(\.code).filter { codes.contains($0) }.joined(separator: ",")
    }

    /// Human-readable summary for the picker label.
    static func summary(for codes: Set<String>) -> String {
        if codes.isEmpty { return "Auto-detect (all)" }
        return labels(for: codes).joined(separator: ", ")
    }

    /// Catalog-ordered labels for a set of codes (e.g. for an LLM prompt hint).
    static func labels(for codes: Set<String>) -> [String] {
        known.filter { codes.contains($0.code) }.map(\.label)
    }

    /// The language policy for a given selection: exactly one selected → pin
    /// it; none → free auto-detect; several → detect, but only among those.
    static func selection(for codes: Set<String>) -> LanguageSelection {
        switch codes.count {
        case 0: return .auto
        case 1: return .pinned(codes.first!)
        default: return .restricted(codes)
        }
    }

    /// Given detection output, the language to pin: the detected language if
    /// the user selected it, otherwise the best-scoring selected candidate —
    /// so detection can never land on a language outside the selection.
    static func pick(detected: String, probs: [String: Float], among candidates: Set<String>) -> String {
        if candidates.contains(detected) { return detected }
        return candidates.max { (probs[$0] ?? 0) < (probs[$1] ?? 0) } ?? ""
    }
}

/// How the transcriber should choose the language of a recording.
enum LanguageSelection: Equatable {
    case auto                      // no preference — the model detects freely
    case pinned(String)            // exactly one language, always
    case restricted(Set<String>)   // detect, but only among these codes
}

/// Defaults applied on first launch.
enum DefaultPref {
    /// Default user-prompt template. `{{input}}` is replaced with the transcript.
    /// The system prompt (which also injects the vocabulary list) is controlled
    /// by the app, not the user.
    static let rewritePromptTemplate = """
    Clean up the following speech-to-text transcript. Fix typos, punctuation, and \
    capitalization without changing the meaning or adding content. Return only the \
    corrected transcript.

    {{input}}
    """

    static func registerDefaults() {
        var defaults: [String: Any] = [:]
        for event in SoundEvent.allCases {
            defaults[event.enabledKey] = true
            defaults[event.nameKey] = event.defaultSound
        }
        UserDefaults.standard.register(defaults: defaults)
        UserDefaults.standard.register(defaults: [
            PrefKey.soundsEnabled: true,
            PrefKey.soundVolume: 1.0,
            PrefKey.selectedModel: "base",
            PrefKey.transcriptionMode: TranscriptionMode.batch.rawValue,
            PrefKey.outputBehavior: OutputBehavior.copyPaste.rawValue,
            PrefKey.restoreClipboard: false,
            PrefKey.realtimeInsertion: RealtimeInsertion.onStop.rawValue,
            PrefKey.fnEnabled: false,
            PrefKey.fnMode: FnMode.holdPTT.rawValue,
            PrefKey.rewriteEnabled: false,
            PrefKey.rewriteProvider: RewriteProvider.anthropic.rawValue,
            PrefKey.rewriteModel: "claude-haiku-4-5-20251001",
            PrefKey.rewriteBaseURL: "https://api.openai.com/v1",
            PrefKey.rewritePrompt: DefaultPref.rewritePromptTemplate,
            PrefKey.language: "en",
            PrefKey.preferredLanguages: "en",   // preserve today's English default; deselect for auto
            PrefKey.inputDeviceUID: "",   // follow system default
            PrefKey.quickActionsEnabled: false,
            PrefKey.quickActionsLLMFallback: false,
            PrefKey.quickActionsModifier: QuickActionModifier.command.rawValue
        ])
    }
}
