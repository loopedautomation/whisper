import Foundation
import SwiftUI

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
    static let language = "language"                       // whisper language hint, "" = auto
    static let soundsEnabled = "soundsEnabled"            // master sound toggle
    static let inputDeviceUID = "inputDeviceUID"          // audio input device UID, "" = system default
    static let soundVolume = "soundVolume"                // 0.0...1.0
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
            PrefKey.inputDeviceUID: ""   // follow system default
        ])
    }
}
