import Foundation
import NaturalLanguage

/// Identifies what language a piece of text is in, on-device.
///
/// Style is per-language: handing a model English samples while it rewrites a
/// German paragraph pulls the result toward English rhythm and vocabulary, so
/// a wrong answer here is worse than no answer. Everything below is therefore
/// biased toward returning `nil` — "don't know" — rather than a confident guess
/// on evidence too thin to support one.
enum LanguageDetector {

    /// Below this, detection on short strings is close to a coin toss.
    private static let minimumConfidence = 0.65
    /// Fewer words than this and even a confident answer isn't trustworthy —
    /// "ok thanks" looks like half a dozen languages.
    private static let minimumWords = 4

    /// The dominant language as an ISO 639-1 code ("en", "de"), or `nil` when
    /// the text is too short or too ambiguous to call.
    static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StyleCorpus.wordCount(trimmed) >= minimumWords else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence else { return nil }
        // Normalize to the bare language code: NLLanguage can carry a script or
        // region ("zh-Hans"), and the corpus only cares about the language.
        return normalize(language.rawValue)
    }

    /// "zh-Hans" → "zh", "en-GB" → "en".
    static func normalize(_ code: String) -> String? {
        let base = code.split(separator: "-").first.map(String.init)?.lowercased()
        guard let base, !base.isEmpty, base != "und" else { return nil }
        return base
    }

    /// Human-readable name for the Settings display, falling back to the code
    /// itself for anything the system doesn't name.
    static func displayName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}
