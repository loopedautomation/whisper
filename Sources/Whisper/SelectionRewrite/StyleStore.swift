import Foundation
import AppKit
import Combine

/// Loads the hand-edited `style.json` from `~/Library/Application Support/
/// Looped Whisper/`, creating a commented starter file on first run.
///
/// A config that fails to parse leaves `profile` nil and `loadError` set, and
/// the rewrite refuses to run. That is deliberate: falling back to defaults
/// would mean a rule the user believes is on is quietly off, which is the one
/// failure they would never catch.
@MainActor
final class StyleStore: ObservableObject {
    @Published private(set) var profile: StyleProfile?
    /// Human-readable reason the config was rejected, naming the exact rule.
    @Published private(set) var loadError: String?

    let fileURL = AppPaths.styleFile

    init() {
        createStarterIfNeeded()
        load()
    }

    /// Re-reads from disk. Called when the Style settings tab appears and after
    /// the user edits the file, so hand-edits take effect without a relaunch.
    func reload() { load() }

    func revealInFinder() {
        createStarterIfNeeded()
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Writes an accepted rule into `style.json`. Returns false (leaving the
    /// file untouched) if the config isn't currently parseable — the app must
    /// never overwrite a file the user is mid-edit on.
    @discardableResult
    func accept(_ proposal: StyleProposal, replacement: String? = nil) -> Bool {
        // Re-read first: this rewrites the whole file from the parsed model, so
        // acting on a stale copy would silently discard hand-edits made since
        // the tab was opened.
        load()
        guard let current = profile else { return false }
        let updated = current.applying(proposal, replacement: replacement)
        guard let data = try? updated.encoded() else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            loadError = "Couldn't write style.json: \(error.localizedDescription)"
            return false
        }
        load()
        return true
    }

    private func load() {
        // "No file" and "file exists but can't be read" must not be conflated:
        // the first is a fresh install, the second would silently discard every
        // rule the user wrote.
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            profile = .starter
            loadError = nil
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            profile = nil
            loadError = "Couldn't read style.json: \(error.localizedDescription)"
            return
        }
        do {
            profile = try StyleProfile.decode(data)
            loadError = nil
        } catch let error as StyleProfileError {
            profile = nil
            loadError = error.description
        } catch {
            profile = nil
            loadError = "Couldn't read style.json: \(error.localizedDescription)"
        }
    }

    private func createStarterIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? Data(StyleStore.starterFile.utf8).write(to: fileURL, options: .atomic)
    }

    /// Written on first launch. Shows every rule with the repairable/
    /// unrepairable split spelled out, since that distinction is the whole
    /// reason the config has two sections.
    /// `nonisolated` because it's an immutable constant, not main-actor state —
    /// tests and any other non-isolated caller need to read it without hopping
    /// actors (a plain `static let` on a @MainActor type is an error under the
    /// Swift 6 language mode).
    nonisolated static let starterFile = """
    {
      "voice": {
        "description": "Describe how you write. Tone, sentence length, what you avoid.",
        "samples": [
          "Paste a paragraph of your own writing here. Two or three samples is plenty — they are what the rewrite matches your voice against."
        ]
      },

      "prompted": {
        "guidance": [
          "Prefer concrete nouns over abstractions.",
          "Lead with the point, then the reasoning."
        ]
      },

      "enforced": {
        "substitutions": [
          { "find": "\\u2014", "replace": ", " }
        ],
        "straightenQuotes": true,
        "bannedWords": [
          { "word": "leverage", "replacement": "use" },
          { "word": "delve" }
        ],
        "maxWords": null
      }
    }
    """
}
