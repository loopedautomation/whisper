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
}
