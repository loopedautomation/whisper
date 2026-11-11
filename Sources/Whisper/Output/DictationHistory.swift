import Foundation
import AppKit

/// A log of what was dictated, kept on this Mac: to get back a transcript that
/// went to the wrong place, to look over what was said, and to correct what
/// the transcriber got wrong. Text only: no audio is ever stored.
@MainActor
final class DictationHistory: ObservableObject {
    struct Entry: Codable, Equatable, Identifiable {
        var id = UUID()
        var date: Date
        /// The text as it stands: the transcript, or the user's correction.
        var text: String
        /// What the transcriber produced, once the user has corrected it.
        var original: String?

        var isCorrected: Bool { original != nil }
    }

    /// The log keeps this many dictations; the oldest drop off the end.
    nonisolated static let limit = 5_000

    @Published private(set) var entries: [Entry] = []   // newest first

    let fileURL: URL

    init(fileURL: URL = AppPaths.historyFile) {
        self.fileURL = fileURL
        load()
    }

    var latest: String? { entries.first?.text }

    func add(_ text: String, at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries = Self.pruned([Entry(date: date, text: trimmed)] + entries, now: date)
        save()
    }

    /// Replaces an entry's text with the user's correction, remembering what
    /// the transcriber had written. Returns that original, or nil if nothing
    /// changed.
    @discardableResult
    func correct(_ id: UUID, to text: String) -> String? {
        let corrected = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty, let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].text != corrected else { return nil }
        let original = entries[index].original ?? entries[index].text
        entries[index].text = corrected
        // Correcting back to what was transcribed is no correction at all.
        entries[index].original = corrected == original ? nil : original
        save()
        return original
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Newest first, and no more than the limit.
    nonisolated static func pruned(_ entries: [Entry], now: Date) -> [Entry] {
        Array(entries.sorted { $0.date > $1.date }.prefix(limit))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = Self.pruned(stored, now: Date())
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Readable by this user only: it is their dictated text.
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
