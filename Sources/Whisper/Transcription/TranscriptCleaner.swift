import Foundation

/// Deterministic repairs to what the model hands back. Whisper was trained on
/// subtitled video, and on quiet or trailing audio it reproduces what subtitle
/// files end with, or reads its own prompt back.
enum TranscriptCleaner {
    /// Credits Whisper appends to quiet endings. Only ever removed from the very
    /// end of the text: mid-sentence they could be something the user said.
    static let trailingCredits = [
        "Subtitles by the Amara.org community",
        "Untertitel der Amara.org-Community",
        "Sous-titres réalisés par la communauté d'Amara.org",
        "Sous-titres par la communauté d'Amara.org",
        "Sous-titrage Société Radio-Canada",
        "Sous-titrage ST' 501",
    ]

    /// Removes a subtitle credit from the end of `text`, if there is one.
    static func stripTrailingCredits(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            // Compare without the full stop or quote the model puts after it.
            let core = String(result.reversed().drop { ch in
                ch.unicodeScalars.allSatisfy(trailingNoise.contains)
            }.reversed())
            guard let credit = trailingCredits.first(where: {
                core.range(of: $0, options: [.caseInsensitive, .anchored, .backwards]) != nil
            }) else { return result }
            result = String(core.dropLast(credit.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// True when `text` is nothing but the vocabulary prompt read back: two or
    /// more terms and no other words. One term alone is left be, since saying
    /// a single name is an ordinary dictation.
    static func isPromptEcho(_ text: String, vocabulary: [String]) -> Bool {
        var remaining = normalize(text)
        guard !remaining.isEmpty else { return false }
        var matched = 0
        // Longest first, so "Looped Whisper" is consumed before "Looped".
        for term in vocabulary.map(normalize).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            let before = remaining
            remaining = remaining.replacingOccurrences(of: term, with: " ")
            if remaining != before { matched += 1 }
        }
        let leftover = remaining.trimmingCharacters(in: .whitespaces)
        return matched >= 2 && leftover.isEmpty
    }

    // MARK: - helpers

    private static let trailingNoise = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)

    /// Lowercased, with punctuation turned into spaces and runs collapsed.
    private static func normalize(_ text: String) -> String {
        let spaced = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }
}

/// The recognition prompt built from the vocabulary list.
enum VocabularyPrompt {
    /// Whisper's prompt slot holds 223 tokens, and an overlong prompt is cut
    /// from the front, which would drop the terms at the top of the list. Stay
    /// well inside it.
    static let characterLimit = 500

    /// The terms joined for the prompt, in list order, stopping before the
    /// limit. Terms nearer the top of the list are the ones kept.
    static func build(_ terms: [String], limit: Int = characterLimit) -> String {
        var prompt = ""
        for term in terms.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !term.isEmpty {
            let next = prompt.isEmpty ? term : prompt + ", " + term
            guard next.count <= limit else { break }
            prompt = next
        }
        return prompt
    }
}
