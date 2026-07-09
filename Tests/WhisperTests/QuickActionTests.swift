import XCTest
@testable import Whisper

final class QuickActionTests: XCTestCase {

    private func action(_ name: String = "Open GitHub",
                        triggers: [String] = ["take me to github", "open github"],
                        kind: QuickActionKind = .openURL,
                        target: String = "https://github.com",
                        enabled: Bool = true) -> QuickAction {
        QuickAction(name: name, triggers: triggers, kind: kind, target: target, enabled: enabled)
    }

    // MARK: - normalization

    func testNormalizeStripsCaseWhitespaceAndTrailingPunctuation() {
        XCTAssertEqual(QuickActionMatcher.normalize("  Take me to  GitHub. "), "take me to github")
        XCTAssertEqual(QuickActionMatcher.normalize("Open GitHub!"), "open github")
    }

    // MARK: - matching

    func testExactTriggerMatches() {
        let a = action()
        let m = QuickActionMatcher.match("Take me to GitHub.", actions: [a])
        XCTAssertEqual(m?.action.id, a.id)
        XCTAssertNil(m?.query)
    }

    func testDisabledActionDoesNotMatch() {
        let a = action(enabled: false)
        XCTAssertNil(QuickActionMatcher.match("take me to github", actions: [a]))
    }

    func testOrdinaryDictationDoesNotMatch() {
        let a = action()
        XCTAssertNil(QuickActionMatcher.match("I pushed the fix to github earlier today", actions: [a]))
    }

    func testPrefixTriggerExtractsQuery() {
        let search = action("Search", triggers: ["search for"],
                            target: "https://google.com/search?q={{query}}")
        let m = QuickActionMatcher.match("Search for Swift actors.", actions: [search])
        XCTAssertEqual(m?.action.id, search.id)
        XCTAssertEqual(m?.query, "swift actors")
    }

    func testPrefixWithoutQueryPlaceholderDoesNotMatch() {
        // "open github now please" must not silently drop the remainder.
        let a = action()
        XCTAssertNil(QuickActionMatcher.match("open github now please", actions: [a]))
    }

    func testLongestPrefixTriggerWins() {
        let generic = action("Search", triggers: ["search"], target: "https://a.com?q={{query}}")
        let specific = action("Search docs", triggers: ["search docs for"], target: "https://b.com?q={{query}}")
        let m = QuickActionMatcher.match("search docs for actors", actions: [generic, specific])
        XCTAssertEqual(m?.action.id, specific.id)
        XCTAssertEqual(m?.query, "actors")
    }

    // MARK: - executor helpers

    func testNormalizeURLStringAddsScheme() {
        XCTAssertEqual(QuickActionExecutor.normalizeURLString("github.com"), "https://github.com")
        XCTAssertEqual(QuickActionExecutor.normalizeURLString("https://github.com"), "https://github.com")
    }

    func testSubstitutePercentEncodesQueryForURLs() {
        let out = QuickActionExecutor.substitute(
            "https://g.com/search?q={{query}}", query: "swift & actors", encodeForURL: true)
        XCTAssertEqual(out, "https://g.com/search?q=swift%20%26%20actors")
    }

    // MARK: - classifier parsing

    func testClassifierParsesMatch() {
        let a = action()
        let reply = "{\"action_id\": \"\(a.id.uuidString)\", \"query\": null}"
        let m = QuickActionClassifier.parse(reply, actions: [a])
        XCTAssertEqual(m?.actionID, a.id)
        XCTAssertNil(m?.query)
    }

    func testClassifierParsesFencedReplyWithQuery() {
        let a = action()
        let reply = "```json\n{\"action_id\": \"\(a.id.uuidString)\", \"query\": \"cats\"}\n```"
        let m = QuickActionClassifier.parse(reply, actions: [a])
        XCTAssertEqual(m?.actionID, a.id)
        XCTAssertEqual(m?.query, "cats")
    }

    func testClassifierRejectsNullUnknownIdAndGarbage() {
        let a = action()
        XCTAssertNil(QuickActionClassifier.parse("{\"action_id\": null}", actions: [a]))
        XCTAssertNil(QuickActionClassifier.parse("{\"action_id\": \"\(UUID().uuidString)\"}", actions: [a]))
        XCTAssertNil(QuickActionClassifier.parse("Sure! Here's the JSON you asked for.", actions: [a]))
    }
}
