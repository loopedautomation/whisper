import Foundation

/// Strips the packaging models wrap around an answer — code fences, a
/// "Here's the rewritten text:" lead-in, surrounding quotation marks.
///
/// This is not cosmetic. The result is pasted straight into the user's
/// document, so a stray ``` or a lead-in sentence lands in their prose.
enum ResponseUnwrapper {

    /// Peels layers until nothing more comes off. Models combine them freely
    /// ("Here's the rewrite:" *then* a fenced block), so one pass isn't enough.
    static func unwrap(_ text: String) -> String {
        var current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bounded so a pathological input can't spin here.
        for _ in 0..<4 {
            let next = stripQuotes(stripFence(stripPreamble(current)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if next == current { break }
            current = next
        }
        return current
    }

    // MARK: - layers

    /// Words by which the model refers to *its own output*. A lead-in has to
    /// contain one of these, not merely sound conversational.
    ///
    /// This is the load-bearing half of the check. Matching on "here's" or
    /// "i have" alone deletes real content: "I have three concerns:" and
    /// "Here's what we found:" are lines a user writes, and stripping them
    /// silently corrupts the document the rewrite is pasted into.
    private static let outputNouns = [
        "rewrit", "rewrote", "revis", "reword", "rephras", "shorter", "shorten",
        "condens", "simplif", "correct", "cleaned", "polished", "updated",
        "version", "edit", "draft"
    ]

    /// Conversational openers. Optional — they only help confirm a line that
    /// already refers to the output.
    private static let leadIns = [
        "here's", "here is", "here are", "below is", "i've", "i have",
        "this is", "sure", "certainly", "of course", "okay", "ok"
    ]

    static func stripPreamble(_ text: String) -> String {
        guard let newline = text.firstIndex(where: \.isNewline) else { return text }
        let first = text[text.startIndex..<newline].trimmingCharacters(in: .whitespaces)
        let rest = String(text[text.index(after: newline)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty, first.hasSuffix(":"), first.count <= 80 else { return text }

        let lowered = first.lowercased()
        // Must name the output. "Here's what we found:" doesn't, and survives.
        guard outputNouns.contains(where: lowered.contains) else { return text }
        // Either framed as a lead-in ("Here's the rewritten text:") or terse
        // enough to be a label rather than a sentence ("Rewritten:").
        let isLeadIn = leadIns.contains { lowered.hasPrefix($0) || lowered.contains(" \($0) ") }
        let isLabel = lowered.split(separator: " ").count <= 4
        guard isLeadIn || isLabel else { return text }
        return rest
    }

    /// Removes a fence only when it wraps the *entire* reply — a fenced block
    /// in the middle, or one followed by prose, is content the user asked for.
    static func stripFence(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count >= 2,
              lines[0].trimmingCharacters(in: .whitespaces).hasPrefix("```")
        else { return text }
        // The opening fence may carry a language tag; anything else on that
        // line means it isn't a plain fence, so leave the text alone.
        let opener = lines[0].trimmingCharacters(in: .whitespaces).dropFirst(3)
        guard !opener.contains("`"), !opener.contains(" ") else { return text }
        guard let closing = lines.lastIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "```"
        }), closing > 0 else { return text }
        // The closing fence must end the reply. Anything after it is content —
        // an explanation, or the tail of a passage that merely *started* with a
        // fenced block — and discarding it would silently truncate the paste.
        guard lines[(closing + 1)...].allSatisfy({
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return text }
        return lines[1..<closing].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let quotePairs: [(Character, Character)] = [
        ("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}")
    ]

    /// Unwraps matched quotes around the whole reply — but only when that quote
    /// character appears nowhere inside, so genuinely quoted prose (`"Stop," he
    /// said, "now."`) isn't silently mangled.
    static func stripQuotes(_ text: String) -> String {
        guard let first = text.first, let last = text.last, text.count >= 2 else { return text }
        guard quotePairs.contains(where: { $0 == first && $1 == last }) else { return text }
        let inner = text.dropFirst().dropLast()
        guard !inner.contains(first), !inner.contains(last) else { return text }
        return String(inner)
    }
}
