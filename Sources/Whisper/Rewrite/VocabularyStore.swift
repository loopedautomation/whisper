import Foundation
import AppKit
import Combine

/// User-managed list of vocabulary terms (names, jargon, code identifiers),
/// persisted as a plain JSON array at `~/Library/Application Support/Looped
/// Whisper/vocabulary.json`. Used to bias Whisper recognition and to instruct
/// the Phase-2 rewrite to preserve spellings. The file can be hand-edited; the
/// list reloads when the Vocabulary settings tab appears.
@MainActor
final class VocabularyStore: ObservableObject {
    @Published private(set) var terms: [String] = []

    let fileURL = AppPaths.vocabularyFile

    init() {
        migrateLegacyIfNeeded()
        load()
    }

    func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !terms.contains(t) else { return }
        terms.append(t)
        save()
    }

    func remove(at offsets: IndexSet) {
        terms.remove(atOffsets: offsets)
        save()
    }

    func remove(_ term: String) {
        terms.removeAll { $0 == term }
        save()
    }

    /// Re-reads the file from disk (picks up external hand-edits).
    func reload() { load() }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: - persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        terms = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(terms) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// One-time migration from the pre-rename "Whisper" folder.
    private func migrateLegacyIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        let legacy = AppPaths.legacySupport.appendingPathComponent("vocabulary.json")
        guard fm.fileExists(atPath: legacy.path) else { return }
        try? fm.copyItem(at: legacy, to: fileURL)
    }
}
