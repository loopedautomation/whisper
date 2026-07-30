import Foundation

/// Turns accumulated evidence into rule *proposals*.
///
/// Deliberately conservative. These rules land in `StyleEnforcer`, which fails
/// loudly and shows the user an error when something doesn't hold — so five
/// proposals they accept are worth more than fifty they have to audit and turn
/// off. Every rule needs one-sided evidence: "never, across a lot of writing",
/// not "usually".
enum StyleMiner {

    /// Enough writing to believe an absence means something rather than being
    /// an accident of a small sample.
    static let minSamplesForAbsence = 25
    /// Only text the user actually typed can speak to punctuation, so this
    /// threshold is lower — written samples accrue more slowly than dictations.
    static let minWrittenSamplesForPunctuation = 10
    /// A word has to be removed from this many separate rewrites before it
    /// looks like a preference rather than one edit.
    static let minRemovalsForBannedWord = 3

    static func proposals(from corpus: StyleCorpus, profile: StyleProfile) -> [StyleProposal] {
        var found: [StyleProposal] = []
        found.append(contentsOf: punctuationProposals(corpus, profile))
        found.append(contentsOf: bannedWordProposals(corpus, profile))
        return found
    }

    // MARK: - punctuation

    /// Punctuation is mined only from `written` samples. A dictation transcript
    /// says nothing about whether the user types em dashes — Whisper chose that
    /// punctuation, not them — and mining it would manufacture rules from the
    /// transcriber's habits.
    private static func punctuationProposals(
        _ corpus: StyleCorpus, _ profile: StyleProfile
    ) -> [StyleProposal] {
        // Punctuation convention is language-specific: German uses „…" quotes,
        // French spaces its guillemets. Mining across languages would propose
        // an English habit as a universal rule and enforce it against text
        // where it's simply wrong, so evidence comes from one language only —
        // the one the user writes in most.
        let language = corpus.dominantLanguage
        let written = corpus.samples(in: language).filter { $0.source == .written }
        guard written.count >= minWrittenSamplesForPunctuation else { return [] }
        var found: [StyleProposal] = []

        let emDash = "\u{2014}"
        let usesEmDash = written.contains { $0.text.contains(emDash) }
        let alreadyHandled = profile.enforced.substitutions.contains { $0.find == emDash }
        if !usesEmDash && !alreadyHandled {
            found.append(StyleProposal(
                kind: .substitution(find: emDash, replace: ", "),
                evidence: "You haven't used an em dash once in \(written.count) things you've written"
                    + languageSuffix(language, corpus) + "."))
        }

        let curly = ["\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
        let usesCurly = written.contains { sample in curly.contains(where: sample.text.contains) }
        // Only meaningful if they use quotes at all — a corpus with no quote
        // marks of any kind is silence, not a preference.
        let usesStraight = written.contains { $0.text.contains("\"") || $0.text.contains("'") }
        if !usesCurly && usesStraight && !profile.enforced.straightenQuotes {
            found.append(StyleProposal(
                kind: .straightenQuotes,
                evidence: "You always type straight quotes, never curly ones"
                    + languageSuffix(language, corpus) + "."))
        }

        return found
    }

    // MARK: - banned words

    /// Words the user keeps deleting from the app's output, and never uses in
    /// their own writing. Both halves are required: a word they cut once but
    /// use themselves elsewhere is a judgement call, not a rule.
    private static func bannedWordProposals(
        _ corpus: StyleCorpus, _ profile: StyleProfile
    ) -> [StyleProposal] {
        guard !corpus.corrections.isEmpty else { return [] }

        var removalCounts: [String: Int] = [:]
        for correction in corpus.corrections {
            let before = words(correction.produced)
            let after = Set(words(correction.corrected))
            // Count each word once per correction, however often it appeared.
            for word in Set(before) where !after.contains(word) {
                guard !stopWords.contains(word), word.count > 3 else { continue }
                removalCounts[word, default: 0] += 1
            }
        }

        let ownVocabulary = Set(corpus.samples.flatMap { words($0.text) })
        let alreadyBanned = Set(profile.enforced.bannedWords.map { $0.word.lowercased() })

        return removalCounts
            .filter { $0.value >= minRemovalsForBannedWord }
            .filter { !ownVocabulary.contains($0.key) }
            .filter { !alreadyBanned.contains($0.key) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { word, count in
                StyleProposal(
                    kind: .bannedWord(word),
                    evidence: "You removed \"\(word)\" from \(count) rewrites, and never use it yourself.")
            }
    }

    /// Names the language in the evidence, but only when the corpus has more
    /// than one — otherwise it's noise.
    private static func languageSuffix(_ language: String?, _ corpus: StyleCorpus) -> String {
        guard let language, corpus.languageCounts.count > 1 else { return "" }
        return " in \(LanguageDetector.displayName(language))"
    }

    private static func words(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }

    /// Common words carry no style signal, and banning one would be a disaster.
    private static let stopWords: Set<String> = [
        "that", "this", "with", "from", "have", "will", "would", "there", "their",
        "which", "about", "them", "they", "then", "than", "been", "were", "what",
        "when", "your", "some", "into", "more", "just", "also", "only", "very",
        "here", "much", "such", "over", "each", "these", "those", "because"
    ]
}
