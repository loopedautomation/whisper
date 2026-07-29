import Foundation

/// What the user asked for. Recognized intents get a crisp, canonical
/// instruction; anything else is passed through verbatim as `.custom`.
enum RewriteIntent: Equatable {
    case rewrite
    case shorten
    case lengthen
    case fixTypos
    case simplify
    case formalize
    case casualize
    case custom(String)

    /// The instruction actually handed to the model. Recognized intents get
    /// wording that doesn't drift with however the user happened to phrase it
    /// that time — or with whatever the transcriber heard.
    var instruction: String {
        switch self {
        case .rewrite:
            return "Rewrite the text, improving the prose without changing what it says."
        case .shorten:
            return "Make the text shorter. Cut anything that isn't carrying weight, keep every fact."
        case .lengthen:
            return "Expand the text with more detail, using only what is already stated or clearly implied."
        case .fixTypos:
            return "Fix typos, spelling, punctuation, and grammar. Change nothing else — not the wording, not the structure."
        case .simplify:
            return "Simplify the text. Plainer words, shorter sentences, same meaning."
        case .formalize:
            return "Make the text more formal and professional, without inflating it."
        case .casualize:
            return "Make the text more casual and conversational, without padding it."
        case .custom(let text):
            return text
        }
    }
}

/// Turns a spoken command into an intent.
///
/// The transcript arrives noisy — filler words, politeness, false starts — but
/// "um, could you make this shorter please" and "shorter" mean the same thing
/// and must behave identically. Recognition happens here, in code, so it is
/// deterministic and testable without a microphone. The raw transcript is still
/// passed to the model alongside the intent, so nothing is lost when a command
/// falls through to `.custom`.
enum CommandNormalizer {

    struct Command: Equatable {
        /// Exactly what was transcribed (or typed).
        var raw: String
        /// The transcript with filler and politeness removed.
        var cleaned: String
        var intent: RewriteIntent
    }

    static func normalize(_ transcript: String) -> Command {
        let cleaned = clean(transcript)
        return Command(raw: transcript, cleaned: cleaned, intent: intent(for: cleaned))
    }

    // MARK: - cleaning

    /// Multi-word politeness and hedging, removed before tokenizing.
    private static let fillerPhrases = [
        "i would like you to", "i'd like you to", "i want you to", "i need you to",
        "could you please", "would you please", "can you please", "please could you",
        "could you", "would you", "can you", "will you", "you know", "i mean",
        "if you don't mind", "for me", "sort of", "kind of", "a little bit", "a bit"
    ]

    /// Removed wherever they appear. Strictly limited to words that are never
    /// anything but filler.
    private static let fillerWords: Set<String> = [
        "um", "uhm", "uh", "uhh", "erm", "er", "ah", "eh", "hmm", "mhm",
        "please", "okay", "ok", "hey", "yeah"
    ]

    /// Removed only at the start, where they're throat-clearing. Mid-sentence
    /// these carry meaning and stripping them mangles the instruction — "make
    /// it sound *like* a pirate", "make it flow *so* it reads better", "make it
    /// read *well*".
    private static let leadingFillerWords: Set<String> = [
        "so", "and", "then", "now", "actually", "basically", "really", "maybe",
        "alright", "like", "just", "well", "right"
    ]

    /// Imperative wrappers that add nothing once the object is known.
    private static let leadingWrappers = [
        "make it", "make this", "make that", "make the text", "make the selection",
        "rewrite it to be", "rewrite this to be", "turn it into", "turn this into",
        "i want it", "i want this", "have it be", "make it sound"
    ]

    static func clean(_ transcript: String) -> String {
        // Keep apostrophes and hyphens; they carry meaning inside words.
        var text = transcript.lowercased()
        text = String(text.map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" ? $0 : " " })
        text = collapse(text)

        for phrase in fillerPhrases {
            text = collapse(text.replacingOccurrences(of: " \(phrase) ", with: " ",
                                                     options: [], range: nil))
            // Also catch the phrase at either end, where the padding spaces don't exist.
            if text.hasPrefix("\(phrase) ") { text = String(text.dropFirst(phrase.count + 1)) }
            if text.hasSuffix(" \(phrase)") { text = String(text.dropLast(phrase.count + 1)) }
            if text == phrase { text = "" }
        }

        var tokens = collapse(text).split(separator: " ").map(String.init)
        tokens.removeAll { fillerWords.contains($0) }
        while let first = tokens.first, leadingFillerWords.contains(first) {
            tokens.removeFirst()
        }

        var result = tokens.joined(separator: " ")
        for wrapper in leadingWrappers where result.hasPrefix(wrapper + " ") {
            result = String(result.dropFirst(wrapper.count + 1))
            break
        }
        return collapse(result)
    }

    private static func collapse(_ text: String) -> String {
        text.split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - intent

    /// Negated forms, checked before the main table. Without these, "make it
    /// less formal" matches the bare keyword "formal" and returns the exact
    /// opposite of what was asked.
    private static let negatedPhrases: [(String, RewriteIntent)] = [
        ("less formal", .casualize), ("not so formal", .casualize),
        ("not too formal", .casualize), ("less stiff", .casualize),
        ("less casual", .formalize), ("not so casual", .formalize),
        ("less informal", .formalize),
        ("less wordy", .shorten), ("not so long", .shorten), ("less long", .shorten),
        ("less short", .lengthen), ("not so short", .lengthen),
        ("less complex", .simplify), ("not so complex", .simplify)
    ]

    /// Ordered most-specific first. `.shorten` leads because "make it shorter
    /// and fix the typos" is primarily a shortening request — and `.fixTypos`
    /// instructs the model to change nothing else, which would actively forbid
    /// the shortening.
    private static let table: [(RewriteIntent, [String])] = [
        (.shorten, ["shorter", "shorten", "condense", "concise", "brief", "briefer",
                    "trim", "tighten", "cut it down", "cut down", "cut this down",
                    "tldr", "tl dr", "summarize", "summarise", "compress"]),
        (.fixTypos, ["typo", "typos", "spelling", "misspell", "grammar", "grammatical",
                     "proofread", "punctuation", "fix the mistakes", "fix mistakes",
                     "fix the errors", "spellcheck"]),
        (.lengthen, ["longer", "lengthen", "expand", "elaborate", "flesh out",
                     "more detail", "more detailed", "in more depth"]),
        (.simplify, ["simpler", "simplify", "simple", "plain english", "plainer",
                     "easier to read", "less jargon", "dumb it down"]),
        (.formalize, ["more formal", "formal", "professional", "polished", "polish",
                      "business-like", "businesslike"]),
        (.casualize, ["more casual", "casual", "informal", "friendlier", "friendly",
                      "conversational", "relaxed"]),
        (.rewrite, ["rewrite", "reword", "rephrase", "redo", "clean it up", "clean up",
                    "tidy up", "tidy it up", "improve", "better", "fix it up", "polish it"])
    ]

    static func intent(for cleaned: String) -> RewriteIntent {
        // An empty command ("um, please") is a bare "rewrite it".
        guard !cleaned.isEmpty else { return .rewrite }
        let padded = " \(cleaned) "
        // Negations first, or their keyword half matches and inverts the intent.
        for (phrase, intent) in negatedPhrases where padded.contains(" \(phrase) ") {
            return intent
        }
        for (intent, keywords) in table {
            for keyword in keywords where padded.contains(" \(keyword) ") {
                return intent
            }
        }
        return .custom(cleaned)
    }
}
