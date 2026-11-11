import Foundation
import AppKit

/// What the app has learned from the user correcting a past dictation: each
/// entry is something the transcriber wrote and what the user meant instead.
/// Applied to every later transcript, whichever model produced it, so the same
/// mistake isn't made twice. Kept on this Mac as readable JSON.
@MainActor
final class CorrectionStore: ObservableObject {
    struct Replacement: Codable, Equatable, Identifiable {
        var heard: String
        var meant: String
        var addedAt: Date
        var id: String { heard.lowercased() }
    }

    @Published private(set) var replacements: [Replacement] = []   // newest first

    let fileURL: URL

    init(fileURL: URL = AppPaths.correctionsFile) {
        self.fileURL = fileURL
        load()
    }

    /// Learns from one corrected dictation. Returns what was learned, so the
    /// caller can say so. Only swaps distinctive enough to be safe to repeat
    /// are kept: "clawed" for "Claude" is, "to" for "two" is not.
    @discardableResult
    func learn(from original: String, to corrected: String, at date: Date = Date()) -> [Replacement] {
        let learned = CorrectionDiff.replacements(from: original, to: corrected)
            .filter { CorrectionDiff.isDistinctive($0.heard) }
            .map { Replacement(heard: $0.heard, meant: $0.meant, addedAt: date) }
        guard !learned.isEmpty else { return [] }
        // A newer correction for the same words replaces the older one.
        let ids = Set(learned.map(\.id))
        replacements = learned + replacements.filter { !ids.contains($0.id) }
        save()
        return learned
    }

    func remove(_ replacement: Replacement) {
        replacements.removeAll { $0.id == replacement.id }
        save()
    }

    func apply(to text: String) -> String {
        CorrectionDiff.apply(replacements.map { ($0.heard, $0.meant) }, to: text)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        replacements = (try? decoder.decode([Replacement].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(replacements) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }
}

/// Finding what changed between a transcript and its correction, and applying
/// those changes to later text. Pure functions.
enum CorrectionDiff {
    /// The word swaps that turn `original` into `corrected`: each run of words
    /// the user replaced, with what they put there. Words only added or only
    /// removed teach nothing repeatable, and neither do changes of punctuation.
    static func replacements(from original: String, to corrected: String,
                             maxWords: Int = 4) -> [(heard: String, meant: String)] {
        let a = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = corrected.split(whereSeparator: \.isWhitespace).map(String.init)
        let ka = a.map(bare), kb = b.map(bare)

        // Longest common subsequence over the words, punctuation aside.
        var lcs = Array(repeating: Array(repeating: 0, count: kb.count + 1), count: ka.count + 1)
        if !ka.isEmpty, !kb.isEmpty {
            for i in (0..<ka.count).reversed() {
                for j in (0..<kb.count).reversed() {
                    lcs[i][j] = ka[i] == kb[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var result: [(heard: String, meant: String)] = []
        var removed: [String] = [], added: [String] = []
        func flush() {
            defer { removed = []; added = [] }
            guard !removed.isEmpty, !added.isEmpty,
                  removed.count <= maxWords, added.count <= maxWords else { return }
            let heard = removed.joined(separator: " "), meant = added.joined(separator: " ")
            guard !heard.isEmpty, !meant.isEmpty, heard != meant else { return }
            result.append((heard, meant))
        }
        var i = 0, j = 0
        while i < ka.count || j < kb.count {
            if i < ka.count, j < kb.count, ka[i] == kb[j] {
                flush(); i += 1; j += 1
            } else if j < kb.count, i == ka.count || lcs[i][j + 1] >= lcs[i + 1][j] {
                if !kb[j].isEmpty { added.append(kb[j]) }
                j += 1
            } else {
                if !ka[i].isEmpty { removed.append(ka[i]) }
                i += 1
            }
        }
        flush()
        return result
    }

    /// Whether a misheard phrase is safe to replace every time it appears. A
    /// short or very common word is right far more often than it is wrong, so
    /// swapping it everywhere would do more damage than good.
    static func isDistinctive(_ heard: String) -> Bool {
        let words = heard.lowercased().split(separator: " ").map(String.init)
        // Three words in a row seldom turn up by chance, however plain each is.
        if words.count >= 3 { return true }
        return words.contains { $0.count >= 4 && !commonWords.contains($0) }
    }

    /// Replaces each `heard` with its `meant`, whole words only and whatever
    /// its capitalisation. Longer phrases go first, so "clawed code" wins over
    /// "clawed".
    static func apply(_ pairs: [(heard: String, meant: String)], to text: String) -> String {
        var result = text
        for pair in pairs.sorted(by: { $0.heard.count > $1.heard.count }) {
            let words = pair.heard.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: pair.meant))
        }
        return result
    }

    /// Names and jargon in a correction, worth adding to the vocabulary: the
    /// words the user wrote with a capital or a digit in them.
    static func vocabularyTerms(in meant: String) -> [String] {
        let words = meant.split(separator: " ").map(String.init)
        func notable(_ word: String) -> Bool {
            word.count >= 2 && !commonWords.contains(word.lowercased())
                && word.contains { $0.isUppercase || $0.isNumber }
        }
        if words.count > 1, words.allSatisfy(notable) { return [meant] }
        return words.filter(notable)
    }

    /// A word without the punctuation around it. Case is kept: fixing a
    /// capital is a correction too.
    private static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
    }

    private static let commonWords: Set<String> = [
        "about", "after", "again", "also", "always", "another", "around", "because", "been", "before",
        "being", "between", "both", "came", "come", "could", "does", "done", "down", "each", "even",
        "every", "from", "gave", "give", "goes", "going", "gone", "good", "have", "here", "into",
        "just", "keep", "kept", "know", "last", "left", "like", "long", "look", "made", "make",
        "many", "more", "most", "much", "must", "need", "never", "next", "only", "other", "over",
        "said", "same", "seem", "should", "some", "such", "take", "than", "that", "their", "them",
        "then", "there", "these", "they", "thing", "think", "this", "those", "through", "time",
        "took", "under", "until", "upon", "very", "want", "well", "went", "were", "what", "when",
        "where", "which", "while", "will", "with", "would", "your", "yours", "right", "write",
        "know", "knew", "hear", "four", "three", "eight", "weather", "whether", "then", "than",
    ]
}
