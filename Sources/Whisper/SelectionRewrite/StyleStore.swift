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
    /// The whole parsed file: base profile plus any named templates.
    @Published private(set) var config: StyleConfig?

    /// The profile a rewrite uses when no template is named — what the Settings
    /// tab displays, and what mined rules are checked against.
    var profile: StyleProfile? { config?.defaultProfile }

    /// Resolves a template named in a spoken command.
    func profile(named name: String?) -> StyleProfile? {
        config?.profile(named: name ?? config?.defaultTemplate)
    }
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
        guard var current = config else { return false }
        // Mined rules come from the whole corpus, so they belong on the base
        // where every template inherits them.
        current.base = current.base.applying(proposal, replacement: replacement)
        return write(current)
    }

    /// The example templates the starter file ships, for adding to a config
    /// that predates them.
    ///
    /// Needed because `createStarterIfNeeded` only writes when no file exists,
    /// so anyone who had a `style.json` before templates shipped never saw the
    /// examples — and a feature nobody can see is a feature nobody uses.
    nonisolated static let exampleTemplates: [(name: String, overlay: StyleOverlay)] = [
        ("email", StyleOverlay(
            description: "Warmer than usual, still direct. No throat-clearing.",
            guidance: ["Open with the ask, not the context."],
            maxWords: 200)),
        ("slack", StyleOverlay(
            description: "Lowercase, quick, no sign-off.",
            maxWords: 60))
    ]

    /// Writes the example templates into `style.json`, skipping any name the
    /// user already has. Returns false and leaves the file alone if the config
    /// isn't currently parseable.
    @discardableResult
    func addExampleTemplates() -> Bool {
        load()
        guard var current = config else { return false }
        for example in StyleStore.exampleTemplates
        where current.templates[example.name.lowercased()] == nil {
            current.templates[example.name.lowercased()] = example.overlay
            current.order.append(example.name)
        }
        return write(current)
    }

    /// Changes which template applies when the user doesn't name one.
    @discardableResult
    func setDefaultTemplate(_ name: String?) -> Bool {
        load()
        guard var current = config else { return false }
        current.defaultTemplate = name
        return write(current)
    }

    /// Serializes a config back to disk and re-reads it, so `config` and the
    /// file can never disagree about what the rules are.
    private func write(_ updated: StyleConfig) -> Bool {
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
            config = StyleConfig(base: .starter)
            loadError = nil
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            config = nil
            loadError = "Couldn't read style.json: \(error.localizedDescription)"
            return
        }
        do {
            config = try StyleConfig.decode(data)
            loadError = nil
        } catch let error as StyleProfileError {
            config = nil
            loadError = error.description
        } catch {
            config = nil
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
      },

      "templates": {
        "email": {
          "voice": { "description": "Warmer than usual, still direct. No throat-clearing." },
          "prompted": { "guidance": ["Open with the ask, not the context."] },
          "enforced": { "maxWords": 200 }
        },
        "slack": {
          "voice": { "description": "Lowercase, quick, no sign-off." },
          "enforced": { "maxWords": 60 }
        }
      },

      "defaultTemplate": null
    }
    """
}
