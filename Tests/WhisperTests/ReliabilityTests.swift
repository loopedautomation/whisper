import XCTest
@testable import Whisper

final class ReliabilityTests: XCTestCase {
    private let rate = AudioRecorder.targetSampleRate

    private func tone(seconds: Double, amplitude: Float, offset: Float = 0) -> [Float] {
        (0..<Int(rate * seconds)).map { i in
            offset + amplitude * Float(sin(2 * Double.pi * 220 * Double(i) / rate))
        }
    }

    // MARK: silence gate

    func testSilenceIsSilent() {
        XCTAssertTrue(AudioLevel.isSilent([Float](repeating: 0, count: Int(rate))))
        XCTAssertTrue(AudioLevel.isSilent(tone(seconds: 1, amplitude: 0.001)))   // about -63 dBFS
    }

    func testSpeechLevelIsNotSilent() {
        XCTAssertFalse(AudioLevel.isSilent(tone(seconds: 1, amplitude: 0.05)))   // about -29 dBFS
    }

    /// A short word in a long quiet recording still counts: the gate looks at
    /// the loudest moment, not the average.
    func testOneLoudMomentIsNotSilent() {
        let clip = [Float](repeating: 0, count: Int(rate * 3)) + tone(seconds: 0.1, amplitude: 0.1)
        XCTAssertFalse(AudioLevel.isSilent(clip))
    }

    /// A constant offset carries no sound, however large it is.
    func testDCOffsetAloneIsSilent() {
        XCTAssertTrue(AudioLevel.isSilent([Float](repeating: 0.4, count: Int(rate))))
    }

    // MARK: recording tail

    func testTailQuietAfterSpeechEnds() {
        let clip = tone(seconds: 0.5, amplitude: 0.1) + [Float](repeating: 0, count: Int(rate * 0.2))
        XCTAssertTrue(AudioLevel.tailIsQuiet(clip))
    }

    func testTailNotQuietWhileSpeaking() {
        XCTAssertFalse(AudioLevel.tailIsQuiet(tone(seconds: 0.5, amplitude: 0.1)))
    }

    func testTailNotJudgedOnTooLittleAudio() {
        XCTAssertFalse(AudioLevel.tailIsQuiet([Float](repeating: 0, count: 100)))
    }

    // MARK: accidental presses

    func testBriefHoldIsDiscarded() {
        let start = Date()
        XCTAssertTrue(Coordinator.heldTooBriefly(since: start, now: start.addingTimeInterval(0.1)))
        XCTAssertFalse(Coordinator.heldTooBriefly(since: start, now: start.addingTimeInterval(0.4)))
        XCTAssertFalse(Coordinator.heldTooBriefly(since: nil))
    }

    // MARK: transcript clean-up

    func testStripsTrailingSubtitleCredit() {
        XCTAssertEqual(
            TranscriptCleaner.stripTrailingCredits("Send it on Monday. Subtitles by the Amara.org community"),
            "Send it on Monday.")
        XCTAssertEqual(
            TranscriptCleaner.stripTrailingCredits("Bis morgen. Untertitel der Amara.org-Community."),
            "Bis morgen.")
    }

    func testCreditAloneBecomesEmpty() {
        XCTAssertEqual(TranscriptCleaner.stripTrailingCredits(" Sous-titrage Société Radio-Canada "), "")
    }

    func testCreditMidSentenceIsKept() {
        let text = "Subtitles by the Amara.org community are free to use."
        XCTAssertEqual(TranscriptCleaner.stripTrailingCredits(text), text)
    }

    func testOrdinaryTextUntouched() {
        XCTAssertEqual(TranscriptCleaner.stripTrailingCredits("Hello there."), "Hello there.")
    }

    // MARK: vocabulary prompt

    func testPromptKeepsEarlyTermsWithinLimit() {
        let terms = (1...200).map { "Term\($0)" }
        let prompt = VocabularyPrompt.build(terms)
        XCTAssertLessThanOrEqual(prompt.count, VocabularyPrompt.characterLimit)
        XCTAssertTrue(prompt.hasPrefix("Term1, Term2"))
        XCTAssertFalse(prompt.contains("Term200"))
    }

    func testShortListIsJoinedWhole() {
        XCTAssertEqual(VocabularyPrompt.build(["Looped", " Kagiso ", ""]), "Looped, Kagiso")
    }

    func testPromptEchoIsRecognised() {
        let vocabulary = ["Looped", "Kagiso", "VAT201"]
        XCTAssertTrue(TranscriptCleaner.isPromptEcho("Looped, Kagiso, VAT201.", vocabulary: vocabulary))
        XCTAssertTrue(TranscriptCleaner.isPromptEcho("looped kagiso", vocabulary: vocabulary))
    }

    func testRealSentenceWithTermsIsNotAnEcho() {
        let vocabulary = ["Looped", "Kagiso"]
        XCTAssertFalse(TranscriptCleaner.isPromptEcho("Ask Kagiso about Looped.", vocabulary: vocabulary))
        // Saying one name on its own is a normal dictation.
        XCTAssertFalse(TranscriptCleaner.isPromptEcho("Kagiso", vocabulary: vocabulary))
    }

    // MARK: history

    func testHistoryKeepsNewestFirstUpToItsLimit() {
        let now = Date()
        let entries = (0..<(DictationHistory.limit + 5)).map {
            DictationHistory.Entry(date: now.addingTimeInterval(-Double($0)), text: "entry \($0)")
        }
        let pruned = DictationHistory.pruned(entries.shuffled(), now: now)
        XCTAssertEqual(pruned.count, DictationHistory.limit)
        XCTAssertEqual(pruned.first?.text, "entry 0")
    }

    @MainActor
    func testHistoryPersistsAndClears() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let history = DictationHistory(fileURL: url)
        history.add("first")
        history.add("  second  ")
        history.add("   ")
        XCTAssertEqual(history.latest, "second")
        XCTAssertEqual(DictationHistory(fileURL: url).entries.map(\.text), ["second", "first"])

        history.clear()
        XCTAssertTrue(DictationHistory(fileURL: url).entries.isEmpty)
    }

    func testMenuPreviewIsOneShortLine() {
        XCTAssertEqual(MenuBarContent.preview("one\ntwo"), "one two")
        XCTAssertEqual(MenuBarContent.preview(String(repeating: "a", count: 60)).count, 49)
    }
}
