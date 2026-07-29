import Foundation

/// Applies the mechanical half of a `StyleProfile` to a model's reply.
///
/// The prompt asks for these rules too, but asking isn't enough: a model told
/// "never use an em dash" still emits one now and then, and that is precisely
/// the character the user will notice. So every rule that can be satisfied
/// without deciding what the text *means* is applied here in code — no extra
/// round trip, no way to fail. What's left over (a word limit, a banned word
/// with no stated substitute) is reported as a violation for the caller to send
/// back to the model exactly once.
enum StyleEnforcer {

    /// A rule the model broke that code can't fix on its own. `message` is
    /// written to be pasted straight into the retry prompt — naming the breach
    /// precisely ("240 words; the limit is 200") works far better than a vague
    /// "you violated the style rules".
    struct Violation: Equatable {
        var message: String
    }

    struct Result: Equatable {
        var text: String
        /// Empty when the text fully complies.
        var violations: [Violation]

        var isCompliant: Bool { violations.isEmpty }
    }

    /// Repairs what can be repaired, then reports what's left.
    ///
    /// Order matters: repairs run *first* so a substituted em dash is never
    /// counted as a violation, and so the word count is measured on the text
    /// the user will actually receive.
    static func apply(_ text: String, style: StyleProfile.Enforced) -> Result {
        let repaired = repair(text, style: style)
        return Result(text: repaired, violations: violations(in: repaired, style: style))
    }

    // MARK: - repairable rules

    /// Deterministic fixes. Always safe, always applied, cannot fail.
    static func repair(_ text: String, style: StyleProfile.Enforced) -> String {
        var out = text
        for substitution in style.substitutions {
            out = out.replacingOccurrences(of: substitution.find, with: substitution.replace)
        }
        if style.straightenQuotes {
            out = straightenQuotes(out)
        }
        for banned in style.bannedWords {
            guard let replacement = banned.replacement else { continue }
            out = replaceWord(banned.word, with: replacement, in: out)
        }
        return out
    }

    /// Curly quotes and apostrophes → their straight equivalents.
    static func straightenQuotes(_ text: String) -> String {
        var out = text
        for double in ["\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}"] {
            out = out.replacingOccurrences(of: double, with: "\"")
        }
        for single in ["\u{2018}", "\u{2019}", "\u{201A}", "\u{2039}", "\u{203A}"] {
            out = out.replacingOccurrences(of: single, with: "'")
        }
        return out
    }

    /// Whole-word replacement that keeps the original capitalization, so a
    /// banned word at the start of a sentence doesn't come back lowercased.
    static func replaceWord(_ word: String, with replacement: String, in text: String) -> String {
        guard let regex = wordRegex(word) else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += matchCase(of: ns.substring(with: match.range), onto: replacement)
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    // MARK: - unrepairable rules

    /// Rules that survived the repair pass. Each one needs the model to decide
    /// what to cut or how to reword, so code can only report them.
    static func violations(in text: String, style: StyleProfile.Enforced) -> [Violation] {
        var found: [Violation] = []

        if let limit = style.maxWords {
            let count = wordCount(text)
            if count > limit {
                found.append(Violation(
                    message: "the rewrite is \(count) words; the limit is \(limit)"))
            }
        }

        for banned in style.bannedWords where banned.replacement == nil {
            guard containsWord(banned.word, in: text) else { continue }
            found.append(Violation(
                message: "the rewrite uses the banned word \"\(banned.word)\"; "
                    + "reword the sentence to avoid it"))
        }

        return found
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        guard let regex = wordRegex(word) else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    // MARK: - helpers

    /// Case-insensitive whole-word match. `\b` is only a word boundary next to
    /// a word character, so terms starting or ending in punctuation (an emoji,
    /// "C++") get the boundary dropped on that side rather than never matching.
    private static func wordRegex(_ word: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let leading = word.first.map(isWordCharacter) ?? false ? "\\b" : ""
        let trailing = word.last.map(isWordCharacter) ?? false ? "\\b" : ""
        return try? NSRegularExpression(
            pattern: leading + escaped + trailing, options: [.caseInsensitive])
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    /// ALL CAPS → all caps, Capitalized → capitalized, anything else verbatim.
    private static func matchCase(of original: String, onto replacement: String) -> String {
        let letters = original.filter(\.isLetter)
        if letters.count > 1, letters.allSatisfy(\.isUppercase) {
            return replacement.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
