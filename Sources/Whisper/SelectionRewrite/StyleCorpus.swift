import Foundation

/// Roughly "what kind of writing is this" — bucketed by length, which is a
/// crude proxy for register but a reliable one. A corpus full of one-line
/// dictations teaches nothing about how the user writes a long paragraph, so
/// retrieval and readiness are both measured per register rather than globally.
enum StyleRegister: String, Codable, CaseIterable, Equatable, Sendable {
    case brief       // a sentence or two
    case standard    // a paragraph
    case extended    // several paragraphs

    static func of(_ text: String) -> StyleRegister {
        switch StyleCorpus.wordCount(text) {
        case ..<25: return .brief
        case 25..<120: return .standard
        default: return .extended
        }
    }

    var label: String {
        switch self {
        case .brief: return "short"
        case .standard: return "paragraph"
        case .extended: return "long-form"
        }
    }
}

/// Where a sample came from. The distinction matters more than it looks:
/// a dictation transcript is the user's *words*, but the punctuation and
/// capitalization are Whisper's choices, not theirs. So word-level mining can
/// use everything, while anything about punctuation must only look at text the
/// user actually typed.
enum StyleSampleSource: String, Codable, Equatable, Sendable {
    case dictation   // words are the user's; punctuation is the transcriber's
    case written     // captured from their document — all of it is theirs
}

/// A piece of the user's own writing.
struct StyleSample: Codable, Equatable, Sendable {
    var text: String
    var register: StyleRegister
    var source: StyleSampleSource
    var addedAt: Date
    /// ISO 639-1 code, or `nil` when detection wasn't confident.
    ///
    /// Optional so corpus files written before this existed still decode; they
    /// get their language filled in on first load.
    var language: String?
}

/// A rewrite the user then edited. `produced` is what the app pasted;
/// `corrected` is what the text had become by the time they selected it again.
/// The difference is a direct statement of preference, and worth far more than
/// raw samples — it's the only signal here that says what was *wrong*.
struct CorrectionPair: Codable, Equatable, Sendable {
    var produced: String
    var corrected: String
    var addedAt: Date
}

/// How much the app can actually match the user's voice right now.
///
/// The rewrite is never blocked on this — a locked door on first launch would
/// be the worst moment of the product, and correction pairs can only accrue
/// once rewrites are happening. Instead the state is surfaced honestly so the
/// user knows whether they're getting generic prose or their own.
enum StyleReadiness: Equatable {
    /// Nothing learned yet; rewrites run on `style.json` alone.
    case generic
    /// Building up. `needsMoreVariety` distinguishes "not enough writing yet"
    /// from "plenty of writing, but all the same shape" — reporting the latter
    /// as a count would show nonsense like 100/25 and imply waiting is enough.
    case learning(have: Int, need: Int, needsMoreVariety: Bool)
    /// Enough evidence, across enough registers, to match the voice.
    case matched

    var label: String {
        switch self {
        case .generic:
            return "Generic — not matching your voice yet"
        case .learning(let have, _, true):
            return "Learning your style — \(have) samples, but all a similar length"
        case .learning(let have, let need, false):
            return "Learning your style (\(have)/\(need))"
        case .matched:
            return "Matching your style"
        }
    }

    var symbolName: String {
        switch self {
        case .generic: return "circle.dashed"
        case .learning: return "circle.bottomhalf.filled"
        case .matched: return "checkmark.circle.fill"
        }
    }
}

/// A rule mined from the corpus, offered for confirmation.
///
/// Never applied automatically. A rule the user believes is on but isn't is the
/// failure they'd never catch — and a rule that switched itself on without
/// being asked is the same failure wearing a different hat.
struct StyleProposal: Equatable, Identifiable {
    enum Kind: Equatable {
        case substitution(find: String, replace: String)
        case straightenQuotes
        case bannedWord(String)
    }

    var kind: Kind
    /// Why this is being proposed, in the user's terms, with the numbers.
    var evidence: String

    var id: String {
        switch kind {
        case .substitution(let find, _): return "sub:\(find)"
        case .straightenQuotes: return "quotes"
        case .bannedWord(let word): return "ban:\(word)"
        }
    }

    var title: String {
        switch kind {
        case .substitution(let find, let replace):
            return "Never use \"\(find)\" — use \"\(replace)\" instead"
        case .straightenQuotes:
            return "Always use straight quotes and apostrophes"
        case .bannedWord(let word):
            return "Never use the word \"\(word)\""
        }
    }

    /// Banned words are the one proposal that lands in the unrepairable tier
    /// unless the user supplies a replacement, so the UI offers a field for it.
    var acceptsReplacement: Bool {
        if case .bannedWord = kind { return true }
        return false
    }
}

/// The learned half of the user's style: their own writing, plus the edits they
/// made to the app's output. Persisted as plain JSON next to `style.json` and
/// never leaves the machine except as the handful of samples retrieval picks
/// for a given rewrite.
struct StyleCorpus: Codable, Equatable, Sendable {
    var samples: [StyleSample] = []
    var corrections: [CorrectionPair] = []
    /// Rewrites the app has pasted but not yet seen edited. Kept so a selection
    /// captured days later can still be recognized as an edited version of our
    /// own output — which means this has to survive a restart, not live in
    /// memory.
    var pendingOutputs: [PendingOutput] = []

    struct PendingOutput: Codable, Equatable, Sendable {
        var text: String
        var producedAt: Date
    }

    // Bounded so the file can't grow without limit; oldest entries fall off.
    static let maxSamples = 400
    static let maxCorrections = 60
    /// Generous, because an evicted output is one the app will later mistake
    /// for the user's own writing and harvest. Cheap to keep: text only.
    static let maxPendingOutputs = 200
    /// After this, an unedited output is assumed to have been accepted as-is.
    static let pendingOutputLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// Identical to something we pasted — accepted unchanged, no signal.
    static let unchangedThreshold = 0.98
    /// Similar enough to be our text after an edit; below this it's different
    /// text entirely and belongs in the corpus as the user's own writing.
    static let editedThreshold = 0.55

    /// What a freshly captured selection turned out to be.
    enum SelectionOrigin: Equatable {
        /// The user's own writing — harvest it.
        case userWriting
        /// Our own output, unedited. Not their voice, so it must not become a
        /// sample, or the corpus slowly fills with the model's prose.
        case unchangedOutput
        /// Our output after they edited it — the correction signal.
        case editedOutput(produced: String)
    }

    /// Classifies a selection against what the app has recently pasted.
    func classify(_ selection: String, now: Date = Date()) -> SelectionOrigin {
        let live = pendingOutputs.filter {
            now.timeIntervalSince($0.producedAt) < StyleCorpus.pendingOutputLifetime
        }
        let best = live
            .map { ($0, TextSimilarity.ratio($0.text, selection)) }
            .max { $0.1 < $1.1 }
        guard let (output, score) = best else { return .userWriting }
        if score >= StyleCorpus.unchangedThreshold { return .unchangedOutput }
        if score >= StyleCorpus.editedThreshold { return .editedOutput(produced: output.text) }
        return .userWriting
    }

    mutating func noteProduced(_ text: String, at date: Date = Date()) {
        pendingOutputs.append(PendingOutput(text: text, producedAt: date))
        if pendingOutputs.count > StyleCorpus.maxPendingOutputs {
            pendingOutputs.removeFirst(pendingOutputs.count - StyleCorpus.maxPendingOutputs)
        }
    }

    /// Drops a pending output once it has yielded its correction, so one edit
    /// can't be counted repeatedly.
    mutating func consumePendingOutput(_ text: String) {
        pendingOutputs.removeAll { $0.text == text }
    }
    /// Below this a sample is too short to say anything about voice.
    static let minSampleWords = 6
    /// How far back the near-duplicate check looks. Repeats cluster in time,
    /// so a bounded scan catches essentially all of them at a fixed cost.
    static let duplicateScanDepth = 60
    /// Stored samples are capped so one pasted essay can't dominate the file.
    static let maxSampleWords = 400

    // MARK: - readiness

    static let learningThreshold = 5    // below this, nothing useful to retrieve
    static let matchedThreshold = 25    // enough samples overall
    static let registersForMatch = 2    // …spread across at least this many registers

    /// Readiness for the language the user writes in most — what the menu bar
    /// and Settings show when no particular passage is in play.
    var readiness: StyleReadiness { readiness(in: dominantLanguage) }

    /// Readiness for one language specifically.
    ///
    /// Measured per language because that's how retrieval works: 200 English
    /// samples say nothing about how the user writes German, and reporting a
    /// single global number would promise a voice match that can't be delivered.
    func readiness(in language: String?) -> StyleReadiness {
        let pool = samples(in: language)
        let total = pool.count
        if total < StyleCorpus.learningThreshold { return .generic }
        let covered = Set(pool.map(\.register)).count
        let shortOnVariety = covered < StyleCorpus.registersForMatch
        if total < StyleCorpus.matchedThreshold || shortOnVariety {
            return .learning(have: total, need: StyleCorpus.matchedThreshold,
                             needsMoreVariety: shortOnVariety && total >= StyleCorpus.matchedThreshold)
        }
        return .matched
    }

    func sampleCount(in register: StyleRegister) -> Int {
        samples.filter { $0.register == register }.count
    }

    /// Samples in one language. A `nil` language means "all of them" — the
    /// honest behaviour when we can't tell what the passage is written in.
    func samples(in language: String?) -> [StyleSample] {
        guard let language else { return samples }
        return samples.filter { $0.language == language }
    }

    /// The language the user writes in most, by sample count. Ties break on the
    /// code so the UI doesn't flicker between equally-sized languages.
    var dominantLanguage: String? {
        var counts: [String: Int] = [:]
        for sample in samples { if let language = sample.language { counts[language, default: 0] += 1 } }
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// Per-language sample counts, most first — the Settings breakdown.
    var languageCounts: [(language: String, count: Int)] {
        var counts: [String: Int] = [:]
        for sample in samples { if let language = sample.language { counts[language, default: 0] += 1 } }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { (language: $0.key, count: $0.value) }
    }

    // MARK: - mutation

    /// Adds a sample if it's substantial enough and not a near-duplicate of one
    /// already held.
    /// `language` may be supplied by the caller when it already knows (dictation
    /// has just detected it); otherwise it's detected from the text.
    mutating func addSample(_ text: String, source: StyleSampleSource,
                            language: String? = nil, at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StyleCorpus.wordCount(trimmed) >= StyleCorpus.minSampleWords else { return }
        let capped = StyleCorpus.truncate(trimmed, toWords: StyleCorpus.maxSampleWords)
        // Re-dictating the same sentence shouldn't count twice. Only the most
        // recent samples of a comparable length are checked: edit distance is
        // quadratic in word count, and running it against the whole corpus on
        // every dictation is a visible hitch once the corpus fills up.
        let words = StyleCorpus.wordCount(capped)
        let plausibleDuplicate = samples.suffix(StyleCorpus.duplicateScanDepth).contains { sample in
            let existing = StyleCorpus.wordCount(sample.text)
            guard existing * 4 > words, words * 4 > existing else { return false }
            return TextSimilarity.ratio(sample.text, capped) > 0.9
        }
        guard !plausibleDuplicate else { return }
        samples.append(StyleSample(
            text: capped, register: .of(capped), source: source, addedAt: date,
            language: language ?? LanguageDetector.detect(capped)))
        if samples.count > StyleCorpus.maxSamples {
            samples.removeFirst(samples.count - StyleCorpus.maxSamples)
        }
    }

    mutating func addCorrection(produced: String, corrected: String, at date: Date = Date()) {
        corrections.append(CorrectionPair(
            produced: StyleCorpus.truncate(produced, toWords: StyleCorpus.maxSampleWords),
            corrected: StyleCorpus.truncate(corrected, toWords: StyleCorpus.maxSampleWords),
            addedAt: date))
        if corrections.count > StyleCorpus.maxCorrections {
            corrections.removeFirst(corrections.count - StyleCorpus.maxCorrections)
        }
    }

    // MARK: - retrieval

    /// The samples to show the model for this particular passage.
    ///
    /// Same-register samples first: three one-line dictations teach nothing
    /// useful about rewriting a long paragraph, and sending them anyway is
    /// worse than sending nothing, because they argue for the wrong rhythm.
    func samples(for passage: String, limit: Int = 3) -> [StyleSample] {
        // Language before anything else. English samples offered as "your
        // voice" while rewriting German actively drag the result toward English
        // rhythm and vocabulary — worse than sending no samples at all. When
        // the passage's language can't be determined, fall back to everything
        // rather than guessing.
        let language = LanguageDetector.detect(passage)
        let pool = samples(in: language)
        guard pool.count >= StyleCorpus.learningThreshold else { return [] }

        let target = StyleRegister.of(passage)
        let targetWords = max(StyleCorpus.wordCount(passage), 1)
        // Prefer the passage's own register outright. Only when that register
        // is unrepresented do off-register samples get used — a mediocre
        // reference still beats none, but padding a good set with wrong-shaped
        // samples argues for the wrong rhythm.
        let sameRegister = pool.filter { $0.register == target }
        let candidates = sameRegister.isEmpty ? pool : sameRegister
        let scored = candidates.map { sample -> (StyleSample, Double) in
            // Closer in length is closer in shape; log-ratio so a 10× gap is
            // penalized much harder than a 2× one.
            let ratio = Double(StyleCorpus.wordCount(sample.text)) / Double(targetWords)
            return (sample, -abs(log(max(ratio, 0.01))))
        }
        return scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                // Deterministic tie-breaks: newer first, then text, so the same
                // corpus always yields the same prompt.
                if $0.0.addedAt != $1.0.addedAt { return $0.0.addedAt > $1.0.addedAt }
                return $0.0.text < $1.0.text
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Most recent corrections, newest last so the model reads them in order.
    func recentCorrections(limit: Int = 3) -> [CorrectionPair] {
        Array(corrections.suffix(limit))
    }

    // MARK: - helpers

    /// Fills in languages for samples stored before this was recorded.
    /// Returns true when anything changed, so the caller knows to save.
    mutating func backfillLanguages() -> Bool {
        var changed = false
        for index in samples.indices where samples[index].language == nil {
            guard let detected = LanguageDetector.detect(samples[index].text) else { continue }
            samples[index].language = detected
            changed = true
        }
        return changed
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    static func truncate(_ text: String, toWords limit: Int) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count > limit else { return text }
        return words.prefix(limit).joined(separator: " ")
    }
}

// MARK: - similarity

/// Word-level similarity, used to decide whether a selection is an edited
/// version of something the app pasted earlier.
enum TextSimilarity {
    /// 1.0 identical, 0.0 nothing in common. Compares words rather than
    /// characters so a reworded sentence scores low while a two-word tweak to a
    /// paragraph scores high — which is exactly the distinction that separates
    /// "the user edited our output" from "this is different text entirely".
    static func ratio(_ a: String, _ b: String) -> Double {
        let x = tokens(a), y = tokens(b)
        if x.isEmpty && y.isEmpty { return 1 }
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        let distance = editDistance(x, y)
        return 1 - Double(distance) / Double(max(x.count, y.count))
    }

    private static func tokens(_ text: String) -> [String] {
        // Case- and punctuation-insensitive: re-punctuating a sentence is an
        // edit we want to notice, but it shouldn't read as a different text.
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        // Bounded so a very long passage can't make this quadratic cost bite.
        return String(cleaned).split(separator: " ").prefix(400).map(String.init)
    }

    private static func editDistance(_ a: [String], _ b: [String]) -> Int {
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        guard !a.isEmpty else { return b.count }
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
