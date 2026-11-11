import XCTest
@testable import Whisper

/// Correcting a past dictation is how the app learns. These pin what it takes
/// from a correction, and that it never learns something that would damage
/// ordinary text.
final class CorrectionTests: XCTestCase {

    private func swaps(_ original: String, _ corrected: String) -> [String] {
        CorrectionDiff.replacements(from: original, to: corrected).map { "\($0.heard)>\($0.meant)" }
    }

    func testFindsAReplacedWord() {
        XCTAssertEqual(swaps("ask clawed to review it", "ask Claude to review it"), ["clawed>Claude"])
    }

    func testFindsAReplacedPhraseAndSeveralSwaps() {
        XCTAssertEqual(
            swaps("open clawed code and run the vat two oh one report",
                  "open Claude Code and run the VAT201 report"),
            ["clawed code>Claude Code", "vat two oh one>VAT201"])
    }

    func testCapitalisationIsACorrection() {
        XCTAssertEqual(swaps("send it to looped today", "send it to Looped today"), ["looped>Looped"])
    }

    func testPunctuationAloneTeachesNothing() {
        XCTAssertEqual(swaps("hello there how are you", "Hello there, how are you?").count, 1)   // hello>Hello only
        XCTAssertEqual(swaps("fine thanks", "fine, thanks."), [])
    }

    func testAddedOrRemovedWordsTeachNothing() {
        XCTAssertEqual(swaps("send the report", "please send the report today"), [])
        XCTAssertEqual(swaps("um send the report", "send the report"), [])
    }

    func testARewriteOfTheWholeThingTeachesNothing() {
        XCTAssertEqual(swaps("one two three four five six", "completely different words in this sentence here"), [])
    }

    func testOnlyDistinctiveWordsAreSafeToRepeat() {
        XCTAssertTrue(CorrectionDiff.isDistinctive("clawed"))
        XCTAssertTrue(CorrectionDiff.isDistinctive("vat two oh one"))
        XCTAssertFalse(CorrectionDiff.isDistinctive("to"))
        XCTAssertFalse(CorrectionDiff.isDistinctive("there"))
        XCTAssertFalse(CorrectionDiff.isDistinctive("to the"))
    }

    func testAppliesWholeWordsWhateverTheirCase() {
        let pairs = [(heard: "clawed", meant: "Claude"), (heard: "clawed code", meant: "Claude Code")]
        XCTAssertEqual(CorrectionDiff.apply(pairs, to: "Clawed said to open clawed  code."),
                       "Claude said to open Claude Code.")
        // Not inside another word.
        XCTAssertEqual(CorrectionDiff.apply(pairs, to: "the cat was declawed"), "the cat was declawed")
    }

    func testReplacementTextIsTakenLiterally() {
        let pairs = [(heard: "price tag", meant: "$1 (net)")]
        XCTAssertEqual(CorrectionDiff.apply(pairs, to: "the price tag is high"), "the $1 (net) is high")
    }

    func testVocabularyTakesNamesAndJargon() {
        XCTAssertEqual(CorrectionDiff.vocabularyTerms(in: "Claude Code"), ["Claude Code"])
        XCTAssertEqual(CorrectionDiff.vocabularyTerms(in: "the VAT201 form"), ["VAT201"])
        XCTAssertEqual(CorrectionDiff.vocabularyTerms(in: "their"), [])
        XCTAssertEqual(CorrectionDiff.vocabularyTerms(in: "There"), [])
    }

    @MainActor
    func testStoreLearnsPersistsAppliesAndForgets() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-corrections-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = CorrectionStore(fileURL: url)
        // "to" for "two" is too common to repeat; "clawed" is kept.
        let learned = store.learn(from: "ask clawed for to copies", to: "ask Claude for two copies")
        XCTAssertEqual(learned.map(\.heard), ["clawed"])

        let reloaded = CorrectionStore(fileURL: url)
        XCTAssertEqual(reloaded.apply(to: "clawed is going to help"), "Claude is going to help")

        // A newer correction for the same words wins.
        reloaded.learn(from: "clawed", to: "Claud")
        XCTAssertEqual(reloaded.replacements.count, 1)
        XCTAssertEqual(reloaded.apply(to: "clawed"), "Claud")

        reloaded.remove(reloaded.replacements[0])
        XCTAssertEqual(CorrectionStore(fileURL: url).apply(to: "clawed"), "clawed")
    }

    @MainActor
    func testHistoryRemembersWhatWasTranscribed() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let history = DictationHistory(fileURL: url)
        history.add("ask clawed")
        let id = try XCTUnwrap(history.entries.first?.id)

        XCTAssertEqual(history.correct(id, to: "ask Claude"), "ask clawed")
        // A second correction still measures from the transcript.
        XCTAssertEqual(history.correct(id, to: "Ask Claude."), "ask clawed")
        let stored = try XCTUnwrap(DictationHistory(fileURL: url).entries.first)
        XCTAssertEqual(stored.text, "Ask Claude.")
        XCTAssertEqual(stored.original, "ask clawed")

        // Unchanged text is not a correction; putting it back clears the mark.
        XCTAssertNil(history.correct(id, to: "Ask Claude."))
        history.correct(id, to: "ask clawed")
        XCTAssertFalse(try XCTUnwrap(history.entries.first).isCorrected)
    }

    /// A history file written before corrections existed has no `original`.
    @MainActor
    func testReadsHistoryFromBeforeCorrections() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = #"[{"id":"\#(UUID().uuidString)","date":0,"text":"an old dictation"}]"#
        try old.data(using: .utf8)!.write(to: url)
        XCTAssertEqual(DictationHistory(fileURL: url).entries.map(\.text), ["an old dictation"])
    }
}
