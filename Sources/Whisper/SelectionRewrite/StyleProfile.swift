import Foundation

/// The user's writing style, edited once by hand in `style.json`.
///
/// The split between `prompted` and `enforced` is the point of this type. A
/// model told "never use an em dash" still produces them occasionally — often
/// enough that the feature feels broken, because an em dash is exactly the
/// thing a careful writer notices. So mechanical rules live in `enforced` and
/// are applied (or checked) in code after the model replies; everything that
/// needs judgement lives in `prompted` and rides in the system prompt.
///
/// See `StyleEnforcer` for how each enforced rule is honored.
struct StyleProfile: Equatable {
    var voice = Voice()
    var prompted = Prompted()
    var enforced = Enforced()

    /// Who the user is as a writer — description plus real samples to match
    /// the voice against. Prompted only; nothing here is mechanically checkable.
    struct Voice: Equatable {
        var description: String = ""
        var samples: [String] = []
    }

    /// Free-form guidance handed to the model verbatim.
    struct Prompted: Equatable {
        var guidance: [String] = []
    }

    /// Mechanical rules. Each one is either *repairable* — fixable in code with
    /// no judgement call — or *unrepairable*, needing the model to decide what
    /// the text means. `StyleEnforcer` treats the two tiers very differently.
    struct Enforced: Equatable {
        /// Always-safe literal replacements: em dash → comma, and so on.
        /// Applied in code after every reply. Repairable.
        var substitutions: [Substitution] = []
        /// Curly quotes and apostrophes → straight. Repairable.
        var straightenQuotes = false
        /// Words to avoid. With a `replacement`, repairable — swapped in code,
        /// preserving the original capitalization. Without one, unrepairable:
        /// removing a word without a stated substitute changes the sentence,
        /// so it goes back to the model.
        var bannedWords: [BannedWord] = []
        /// Hard ceiling on word count. Unrepairable — truncating would mangle
        /// the meaning, so an over-long rewrite goes back to the model.
        var maxWords: Int?
    }

    struct Substitution: Equatable {
        var find: String
        var replace: String
    }

    struct BannedWord: Equatable {
        var word: String
        /// `nil` means "never use this, and I'm not telling you what to use
        /// instead" — which is why it can't be repaired mechanically.
        var replacement: String?
    }

    /// Default profile used when no `style.json` exists yet. Deliberately
    /// opinionated about the two substitutions almost everyone wants, so the
    /// enforcement path is live from the first run.
    static let starter = StyleProfile(
        voice: Voice(description: "", samples: []),
        prompted: Prompted(guidance: []),
        enforced: Enforced(
            substitutions: [Substitution(find: "—", replace: ", ")],
            straightenQuotes: true,
            bannedWords: [],
            maxWords: nil))
}

// MARK: - decoding

extension StyleProfile {
    /// Every rule the config understands, as a tree. Used to reject unknown
    /// keys before decoding — a rule the user believes is on but isn't is the
    /// failure they'd never catch, so a typo has to be loud.
    private static let schema: JSONSchema = .object([
        "voice": .object([
            "description": .scalar,
            "samples": .array(.scalar)
        ]),
        "prompted": .object([
            "guidance": .array(.scalar)
        ]),
        "enforced": .object([
            "substitutions": .array(.object(["find": .scalar, "replace": .scalar])),
            "straightenQuotes": .scalar,
            "bannedWords": .array(.object(["word": .scalar, "replacement": .scalar])),
            "maxWords": .scalar
        ])
    ])

    /// Parses `style.json`. Throws `StyleProfileError` on an unknown rule name,
    /// a wrong-typed value, or a nonsensical value (empty banned word, zero
    /// word limit) — never silently ignores any of them.
    static func decode(_ data: Data) throws -> StyleProfile {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw StyleProfileError.malformedJSON(error.localizedDescription)
        }
        guard let object = root as? [String: Any] else {
            throw StyleProfileError.notAnObject
        }
        try schema.validate(object, at: [])

        var profile = StyleProfile()
        if let voice = object["voice"] as? [String: Any] {
            profile.voice.description = try string(voice["description"], at: "voice.description") ?? ""
            profile.voice.samples = try strings(voice["samples"], at: "voice.samples")
        }
        if let prompted = object["prompted"] as? [String: Any] {
            profile.prompted.guidance = try strings(prompted["guidance"], at: "prompted.guidance")
        }
        if let enforced = object["enforced"] as? [String: Any] {
            profile.enforced = try decodeEnforced(enforced)
        }
        return profile
    }

    private static func decodeEnforced(_ o: [String: Any]) throws -> Enforced {
        var e = Enforced()

        for (index, raw) in try array(o["substitutions"], at: "enforced.substitutions").enumerated() {
            let path = "enforced.substitutions[\(index)]"
            guard let entry = raw as? [String: Any] else { throw StyleProfileError.wrongType(path, expected: "object") }
            guard let find = try string(entry["find"], at: "\(path).find"), !find.isEmpty else {
                throw StyleProfileError.invalidValue("\(path).find", reason: "must be a non-empty string")
            }
            // An empty `replace` is legitimate — it means "delete this".
            let replace = try string(entry["replace"], at: "\(path).replace") ?? ""
            e.substitutions.append(Substitution(find: find, replace: replace))
        }

        // `null` reads as "not set" throughout, so a rule can be left in the
        // file as a placeholder without tripping the type check.
        if let quotes = o["straightenQuotes"], !(quotes is NSNull) {
            guard let flag = quotes as? Bool else {
                throw StyleProfileError.wrongType("enforced.straightenQuotes", expected: "boolean")
            }
            e.straightenQuotes = flag
        }

        for (index, raw) in try array(o["bannedWords"], at: "enforced.bannedWords").enumerated() {
            let path = "enforced.bannedWords[\(index)]"
            guard let entry = raw as? [String: Any] else { throw StyleProfileError.wrongType(path, expected: "object") }
            guard let word = try string(entry["word"], at: "\(path).word"), !word.isEmpty else {
                throw StyleProfileError.invalidValue("\(path).word", reason: "must be a non-empty string")
            }
            let replacement = try string(entry["replacement"], at: "\(path).replacement")
            // "replacement": "" would silently delete the word mid-sentence;
            // treat it as "no replacement given" so it goes back to the model.
            e.bannedWords.append(BannedWord(
                word: word,
                replacement: (replacement?.isEmpty ?? true) ? nil : replacement))
        }

        if let raw = o["maxWords"], !(raw is NSNull) {
            // `raw is Bool` is unreliable here: JSON numbers bridge to NSNumber,
            // and `1` satisfies `is Bool` — which would reject a perfectly legal
            // (if daft) limit of one word. Ask CoreFoundation what it really is.
            let number = raw as? NSNumber
            let isBoolean = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            guard let number, !isBoolean,
                  Double(number.intValue) == number.doubleValue else {
                throw StyleProfileError.wrongType("enforced.maxWords", expected: "integer")
            }
            guard number.intValue > 0 else {
                throw StyleProfileError.invalidValue("enforced.maxWords", reason: "must be greater than zero")
            }
            e.maxWords = number.intValue
        }

        return e
    }

    private static func string(_ value: Any?, at path: String) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let s = value as? String else { throw StyleProfileError.wrongType(path, expected: "string") }
        return s
    }

    private static func array(_ value: Any?, at path: String) throws -> [Any] {
        guard let value, !(value is NSNull) else { return [] }
        guard let a = value as? [Any] else { throw StyleProfileError.wrongType(path, expected: "array") }
        return a
    }

    private static func strings(_ value: Any?, at path: String) throws -> [String] {
        try array(value, at: path).enumerated().map { index, element in
            guard let s = element as? String else {
                throw StyleProfileError.wrongType("\(path)[\(index)]", expected: "string")
            }
            return s
        }
    }
}

// MARK: - encoding

extension StyleProfile {
    /// Serializes back to `style.json`.
    ///
    /// Used when the user accepts a mined rule. Everything decoded is written
    /// back, so accepting a proposal never drops a rule — but the file is
    /// re-emitted from the parsed model, so hand-formatting and key order are
    /// normalized. That's the cost of letting the app edit a file the user also
    /// edits by hand, and it's worth it to keep one source of truth.
    func encoded() throws -> Data {
        var enforced: [String: Any] = [
            "straightenQuotes": self.enforced.straightenQuotes,
            "substitutions": self.enforced.substitutions.map {
                ["find": $0.find, "replace": $0.replace]
            },
            "bannedWords": self.enforced.bannedWords.map { banned -> [String: Any] in
                var entry: [String: Any] = ["word": banned.word]
                if let replacement = banned.replacement { entry["replacement"] = replacement }
                return entry
            }
        ]
        // Emitted as null rather than omitted, so the rule stays visible in the
        // file as something the user can fill in.
        enforced["maxWords"] = self.enforced.maxWords ?? NSNull()

        let root: [String: Any] = [
            "voice": ["description": voice.description, "samples": voice.samples],
            "prompted": ["guidance": prompted.guidance],
            "enforced": enforced
        ]
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Returns a copy with `proposal` applied. `replacement`, when given, turns
    /// a banned word from the unrepairable tier into the repairable one.
    func applying(_ proposal: StyleProposal, replacement: String? = nil) -> StyleProfile {
        var copy = self
        switch proposal.kind {
        case .substitution(let find, let replace):
            guard !copy.enforced.substitutions.contains(where: { $0.find == find }) else { break }
            copy.enforced.substitutions.append(Substitution(find: find, replace: replace))
        case .straightenQuotes:
            copy.enforced.straightenQuotes = true
        case .bannedWord(let word):
            guard !copy.enforced.bannedWords.contains(where: {
                $0.word.lowercased() == word.lowercased()
            }) else { break }
            let trimmed = replacement?.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.enforced.bannedWords.append(BannedWord(
                word: word,
                replacement: (trimmed?.isEmpty ?? true) ? nil : trimmed))
        }
        return copy
    }
}

// MARK: - errors

/// Why a `style.json` was rejected. Every case is surfaced to the user with the
/// exact path that broke — a config error must never degrade into "the rule
/// just didn't apply".
enum StyleProfileError: Error, Equatable, CustomStringConvertible {
    case malformedJSON(String)
    case notAnObject
    /// An unrecognized rule name, with the closest real one when there is a
    /// plausible match — typos are the whole reason this check exists.
    case unknownKey(path: String, suggestion: String?)
    case wrongType(String, expected: String)
    case invalidValue(String, reason: String)

    var description: String {
        switch self {
        case .malformedJSON(let detail):
            return "style.json isn't valid JSON: \(detail)"
        case .notAnObject:
            return "style.json must contain a JSON object at the top level"
        case .unknownKey(let path, let suggestion):
            if let suggestion {
                return "Unknown rule \"\(path)\" in style.json — did you mean \"\(suggestion)\"?"
            }
            return "Unknown rule \"\(path)\" in style.json"
        case .wrongType(let path, let expected):
            return "\"\(path)\" in style.json must be \(article(expected)) \(expected)"
        case .invalidValue(let path, let reason):
            return "\"\(path)\" in style.json \(reason)"
        }
    }

    private func article(_ word: String) -> String {
        "aeiou".contains(word.lowercased().first ?? "x") ? "an" : "a"
    }
}

// MARK: - schema walking

/// Minimal shape description, just enough to reject unknown keys with a path.
private indirect enum JSONSchema {
    case object([String: JSONSchema])
    case array(JSONSchema)
    case scalar

    func validate(_ value: Any, at path: [String]) throws {
        // `null` means "not set" everywhere, so it's valid at any node.
        if value is NSNull { return }
        switch self {
        case .scalar:
            return
        case .array(let element):
            // A section of the wrong *type* has to be as loud as an unknown
            // key. Waving it through would leave every rule inside it silently
            // inactive — the exact failure the schema walk exists to prevent.
            guard let items = value as? [Any] else {
                throw StyleProfileError.wrongType(JSONSchema.render(path), expected: "array")
            }
            for (index, item) in items.enumerated() {
                try element.validate(item, at: path + ["[\(index)]"])
            }
        case .object(let fields):
            guard let dict = value as? [String: Any] else {
                throw StyleProfileError.wrongType(JSONSchema.render(path), expected: "object")
            }
            for (key, child) in dict {
                guard let schema = fields[key] else {
                    throw StyleProfileError.unknownKey(
                        path: JSONSchema.render(path + [key]),
                        suggestion: JSONSchema.closest(key, in: Array(fields.keys)))
                }
                try schema.validate(child, at: path + [key])
            }
        }
    }

    /// "enforced.bannedWords[0].word" — array indices attach without a dot.
    static func render(_ path: [String]) -> String {
        path.reduce("") { acc, part in
            if part.hasPrefix("[") { return acc + part }
            return acc.isEmpty ? part : acc + "." + part
        }
    }

    /// Nearest known key by edit distance, when it's close enough to be a
    /// plausible typo rather than a different word entirely.
    private static func closest(_ key: String, in candidates: [String]) -> String? {
        let scored = candidates
            .map { ($0, editDistance(key.lowercased(), $0.lowercased())) }
            .min { $0.1 < $1.1 }
        guard let (candidate, distance) = scored else { return nil }
        let threshold = max(2, candidate.count / 3)
        return distance <= threshold ? candidate : nil
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
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
