import XCTest
import AVFoundation
@testable import Whisper

final class WhisperTests: XCTestCase {

    /// The recorder must resample arbitrary input to 16 kHz mono Float32.
    func testRecorderTargetFormatIs16kMono() throws {
        let recorder = AudioRecorder()
        XCTAssertEqual(AudioRecorder.targetSampleRate, 16_000)
        // Snapshot before any capture should be empty.
        XCTAssertTrue(recorder.snapshot().isEmpty)
    }

    /// Rewrite must fall back to the raw transcript when no API key is present.
    func testRewriteFallsBackWithoutKey() async {
        let cfg = RewriteService.Config(provider: .anthropic, model: "x", apiKey: "", promptTemplate: "{{input}}")
        let result = await RewriteService.rewrite("helo wrld", vocabulary: [], config: cfg)
        XCTAssertEqual(result, "helo wrld")
    }

    /// The languageHint parameter must not disturb the no-key fallback contract.
    func testRewriteFallsBackWithoutKeyEvenWithLanguageHint() async {
        let cfg = RewriteService.Config(provider: .anthropic, model: "x", apiKey: "", promptTemplate: "{{input}}")
        let result = await RewriteService.rewrite("helo wrld", vocabulary: [], config: cfg, languageHint: ["German", "English"])
        XCTAssertEqual(result, "helo wrld")
    }

    /// Empty transcript is returned unchanged regardless of config.
    func testRewriteEmptyTranscript() async {
        let cfg = RewriteService.Config(provider: .anthropic, model: "x", apiKey: "key", promptTemplate: "{{input}}")
        let result = await RewriteService.rewrite("", vocabulary: ["Swift"], config: cfg)
        XCTAssertEqual(result, "")
    }

    func testModelLabelLookup() {
        XCTAssertEqual(WhisperModel.label(for: "base"), "Base")
        XCTAssertEqual(WhisperModel.label(for: "unknown-id"), "unknown-id")
    }

    /// The preferredLanguages pref round-trips through codes(from:)/string(from:),
    /// tolerating whitespace and empty segments, with catalog-stable ordering.
    func testLanguageCodesRoundTrip() {
        let codes = WhisperLanguage.codes(from: "de, fr,,en ")
        XCTAssertEqual(codes, ["en", "de", "fr"])
        XCTAssertEqual(WhisperLanguage.string(from: codes), "en,de,fr")
        XCTAssertEqual(WhisperLanguage.codes(from: ""), [])
    }

    /// None selected → free auto-detect; one → pinned; several → detection
    /// restricted to the selected set.
    func testLanguageSelection() {
        XCTAssertEqual(WhisperLanguage.selection(for: []), .auto)
        XCTAssertEqual(WhisperLanguage.selection(for: ["de"]), .pinned("de"))
        XCTAssertEqual(WhisperLanguage.selection(for: ["de", "en"]), .restricted(["de", "en"]))
    }

    /// The detected language wins when the user selected it; otherwise the
    /// best-scoring selected candidate is pinned — never an unselected one.
    func testLanguagePick() {
        XCTAssertEqual(
            WhisperLanguage.pick(detected: "de", probs: ["de": 0.9, "en": 0.1], among: ["de", "en"]),
            "de")
        XCTAssertEqual(
            WhisperLanguage.pick(detected: "nl", probs: ["nl": 0.6, "de": 0.3, "en": 0.1], among: ["de", "en"]),
            "de")
        XCTAssertEqual(WhisperLanguage.pick(detected: "nl", probs: [:], among: []), "")
    }

    func testLanguageSummary() {
        XCTAssertEqual(WhisperLanguage.summary(for: []), "Auto-detect (all)")
        XCTAssertEqual(WhisperLanguage.summary(for: ["de"]), "German")
        XCTAssertEqual(WhisperLanguage.summary(for: ["de", "en"]), "English, German")
    }

    /// Catalog-ordered labels, used to build the language-repair prompt hint.
    func testLanguageLabels() {
        XCTAssertEqual(WhisperLanguage.labels(for: ["de", "en"]), ["English", "German"])
        XCTAssertEqual(WhisperLanguage.labels(for: []), [])
    }
}
