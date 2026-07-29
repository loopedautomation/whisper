import Foundation

/// Single source of truth for where Looped Whisper stores its data on disk.
///
/// Dev builds (bundle id ending in `.dev`) are isolated from the installed
/// release app: separate data folder, preferences (UserDefaults domain), and
/// keychain — so developing never disturbs your real install. The large model
/// cache is the one thing intentionally **shared**, to avoid re-downloading
/// gigabytes for the dev build.
enum AppPaths {
    /// True when running a development build (separate bundle identifier).
    static var isDev: Bool { Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? false }

    private static var appSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Per-build data directory (vocabulary, etc.). Dev gets its own folder.
    static let support: URL = {
        let name = isDev ? "Looped Whisper (Dev)" : "Looped Whisper"
        let base = appSupportRoot.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// Shared model cache — always the release location, so dev and release reuse
    /// the same downloaded Whisper models.
    static let sharedModels: URL = {
        let dir = appSupportRoot
            .appendingPathComponent("Looped Whisper", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Legacy location used before the app was renamed; migrated on first launch.
    static let legacySupport: URL = appSupportRoot.appendingPathComponent("Whisper", isDirectory: true)

    static let vocabularyFile = support.appendingPathComponent("vocabulary.json")

    static let quickActionsFile = support.appendingPathComponent("quick-actions.json")
    /// Hand-edited writing-style config for the selection rewrite.
    static let styleFile = support.appendingPathComponent("style.json")
    /// Learned writing style: the user's own samples and their edits to past
    /// rewrites. Derived data, never leaves the machine except as the few
    /// samples retrieval picks for a given rewrite.
    static let styleCorpusFile = support.appendingPathComponent("style-corpus.json")
}
