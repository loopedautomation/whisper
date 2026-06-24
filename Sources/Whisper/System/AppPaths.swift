import Foundation

/// Single source of truth for where Looped Whisper stores its data on disk.
enum AppPaths {
    /// ~/Library/Application Support/Looped Whisper
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Looped Whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// Legacy location used before the app was renamed; migrated on first launch.
    static let legacySupport: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Whisper", isDirectory: true)

    static let vocabularyFile = support.appendingPathComponent("vocabulary.json")
}
