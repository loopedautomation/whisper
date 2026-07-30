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
        /// The transcript with filler, politeness and any template name removed.
        var cleaned: String
        var intent: RewriteIntent
        /// A style template the user named ("as an email"), if any. `nil` means
        /// "use whatever the default is".
        var template: String?
    }

    /// `templates` are the names configured in `style.json`; naming one in the
    /// command picks it for this rewrite. Template selection is orthogonal to
    /// intent — "make it shorter as a slack message" is both.
    static func normalize(_ transcript: String, templates: [String] = []) -> Command {
        var cleaned = clean(transcript)
        // Filler-stripping is tuned for English, and some of those words carry
        // meaning elsewhere — German "schreib **um**" means rewrite, but "um"
        // is the commonest English filler. So keep a punctuation-only version
        // for matching non-English keywords against.
        let unstripped = collapse(punctuationOnly(transcript))
        let template = extractTemplate(from: &cleaned, templates: templates)
        return Command(raw: transcript, cleaned: cleaned,
                       intent: intent(for: cleaned, keepingFiller: unstripped),
                       template: template)
    }

    /// Finds a template name in the command and removes it, along with the
    /// connective words around it, so what's left is a clean instruction.
    ///
    /// Longest name first: with templates "email" and "formal email", the
    /// longer one must win or "as a formal email" would match the shorter.
    private static func extractTemplate(from cleaned: inout String, templates: [String]) -> String? {
        let padded = " \(cleaned) "
        for name in templates.sorted(by: { $0.count > $1.count }) {
            let needle = " \(name.lowercased()) "
            guard padded.contains(needle) else { continue }
            var remainder = padded.replacingOccurrences(of: needle, with: " ")
            for connective in [" as a ", " as an ", " as the ", " as ", " in ", " style ",
                               " like a ", " like an ",
                               " als ", " als eine ", " als einen ", " im ", " stil ",
                               " comme ", " comme un ", " comme une ", " en ",
                               " como ", " como un ", " como una "] {
                remainder = remainder.replacingOccurrences(of: connective, with: " ")
            }
            cleaned = remainder.split(separator: " ").joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return name
        }
        return nil
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
        // English
        "um", "uhm", "uh", "uhh", "erm", "er", "ah", "eh", "hmm", "mhm",
        "please", "okay", "ok", "hey", "yeah",
        // German, French, Spanish — only words that are filler in every
        // language the app might see them in. "also" (German for "so") is
        // deliberately absent: it's an ordinary English word.
        "äh", "ähm", "bitte", "danke",
        "euh", "ben", "voilà", "merci",
        "eh", "pues", "vale", "gracias", "porfavor"
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

    /// Lowercased, punctuation reduced to spaces, nothing removed.
    ///
    /// `isLetter` is Unicode-aware, so umlauts and accents survive — turning
    /// "kürzer" into "k rzer" would defeat every localized keyword.
    static func punctuationOnly(_ transcript: String) -> String {
        let lowered = transcript.lowercased()
        return String(lowered.map {
            $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" ? $0 : " "
        })
    }

    static func clean(_ transcript: String) -> String {
        // Keep apostrophes and hyphens; they carry meaning inside words.
        var text = collapse(punctuationOnly(transcript))

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
        (.rewrite, ["style it", "style this", "style", "rewrite", "reword", "rephrase", "redo",
                    "clean it up", "clean up",
                    "tidy up", "tidy it up", "improve", "better", "fix it up", "polish it"])
    ]

    /// Keyword tables for languages other than English.
    ///
    /// Tried after the English table, so an English command is never
    /// misread. A language with no table still works — the instruction falls
    /// through to `.custom` and goes to the model verbatim, which understands
    /// it; what's lost is the canonical phrasing and negation handling, and
    /// that's exactly what these tables restore.
    private static let localizedTables: [(RewriteIntent, [String])] = [
        // German
        (.shorten, ["kürzer", "kuerzer", "kürze", "verkürze", "knapper", "straffen", "zusammenfassen"]),
        (.fixTypos, ["tippfehler", "rechtschreibung", "grammatik", "korrigiere", "fehler korrigieren"]),
        (.lengthen, ["länger", "laenger", "ausführlicher", "erweitere", "mehr detail"]),
        (.simplify, ["einfacher", "vereinfache", "verständlicher"]),
        (.formalize, ["formeller", "förmlicher", "sachlicher", "professioneller"]),
        (.casualize, ["lockerer", "informeller", "legerer", "umgangssprachlicher"]),
        (.rewrite, ["umschreiben", "neu schreiben", "überarbeite", "formuliere", "verbessere",
                    "korrigier das", "schreib um"]),
        // French
        (.shorten, ["plus court", "raccourcis", "raccourcir", "résume", "resume", "condense"]),
        (.fixTypos, ["fautes", "orthographe", "grammaire", "corrige"]),
        (.lengthen, ["plus long", "développe", "developpe", "allonge"]),
        (.simplify, ["simplifie", "plus simple"]),
        (.formalize, ["plus formel", "formel", "professionnel"]),
        (.casualize, ["plus décontracté", "informel", "familier"]),
        (.rewrite, ["réécris", "reecris", "reformule", "améliore", "ameliore"]),
        // Spanish
        (.shorten, ["más corto", "mas corto", "acorta", "resume", "condensa"]),
        (.fixTypos, ["errores", "ortografía", "ortografia", "gramática", "gramatica", "corrige"]),
        (.lengthen, ["más largo", "mas largo", "amplía", "amplia", "extiende"]),
        (.simplify, ["simplifica", "más simple", "mas simple"]),
        (.formalize, ["más formal", "mas formal", "formal", "profesional"]),
        (.casualize, ["más informal", "mas informal", "informal", "coloquial"]),
        (.rewrite, ["reescribe", "reformula", "mejora", "arregla"])
    ]

    /// Negated forms in other languages, checked before their tables for the
    /// same reason the English ones are: "weniger formell" contains "formell".
    private static let localizedNegations: [(String, RewriteIntent)] = [
        ("weniger formell", .casualize), ("nicht so formell", .casualize),
        ("weniger förmlich", .casualize), ("weniger locker", .formalize),
        ("moins formel", .casualize), ("moins long", .shorten),
        ("menos formal", .casualize), ("menos largo", .shorten)
    ]

    /// `keepingFiller` is the same command with punctuation stripped but filler
    /// words intact, used for the non-English tables (see `normalize`).
    static func intent(for cleaned: String, keepingFiller: String = "") -> RewriteIntent {
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
        // English didn't match; try the other languages, negations first, and
        // against the un-stripped text so English filler words can't eat a
        // meaningful particle.
        let localized = keepingFiller.isEmpty ? padded : " \(keepingFiller) "
        for (phrase, intent) in localizedNegations where localized.contains(" \(phrase) ") {
            return intent
        }
        for (intent, keywords) in localizedTables {
            for keyword in keywords where localized.contains(" \(keyword) ") {
                return intent
            }
        }
        return .custom(cleaned)
    }
}
