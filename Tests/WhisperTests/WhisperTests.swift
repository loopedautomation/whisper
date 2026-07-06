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

    /// Exactly one selected language pins it; zero or several mean auto-detect.
    func testLanguageHint() {
        XCTAssertEqual(WhisperLanguage.hint(for: ["de"]), "de")
        XCTAssertEqual(WhisperLanguage.hint(for: []), "")
        XCTAssertEqual(WhisperLanguage.hint(for: ["de", "en"]), "")
    }

    func testLanguageSummary() {
        XCTAssertEqual(WhisperLanguage.summary(for: []), "Auto-detect (all)")
        XCTAssertEqual(WhisperLanguage.summary(for: ["de"]), "German")
        XCTAssertEqual(WhisperLanguage.summary(for: ["de", "en"]), "English, German")
    }
}
