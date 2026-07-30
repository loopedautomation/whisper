import XCTest
@testable import Whisper

/// The `rewrite*` / `selectionRewrite*` → `ai*` fold.
///
/// Worth testing on its own: it runs exactly once per user, on the launch after
/// they upgrade, and getting it wrong looks to them like the app threw away an
/// API setup they'd already done — the kind of bug nobody reports, they just
/// re-enter their key and lose trust.
final class AIConfigMigrationTests: XCTestCase {

    /// A throwaway suite so nothing here touches the real user defaults.
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ai-config-migration-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func legacyKeysRemain() -> Bool {
        ["rewriteProvider", "rewriteModel", "rewriteBaseURL", "rewriteEnabled", "rewritePrompt",
         "selectionRewriteProvider", "selectionRewriteModel", "selectionRewriteBaseURL"]
            .contains { defaults.object(forKey: $0) != nil }
    }

    /// The selection-rewrite config is the one that configured the surviving
    /// feature, so it must win over the retired transcript-cleanup config.
    func testSelectionRewriteConfigWinsOverOldRewriteConfig() {
        defaults.set("openaiCompatible", forKey: "selectionRewriteProvider")
        defaults.set("llama3", forKey: "selectionRewriteModel")
        defaults.set("http://localhost:11434/v1", forKey: "selectionRewriteBaseURL")
        defaults.set("anthropic", forKey: "rewriteProvider")
        defaults.set("claude-haiku-4-5-20251001", forKey: "rewriteModel")

        DefaultPref.migrateLegacyAIConfig(defaults)

        XCTAssertEqual(defaults.string(forKey: PrefKey.aiProvider), "openaiCompatible")
        XCTAssertEqual(defaults.string(forKey: PrefKey.aiModel), "llama3")
        XCTAssertEqual(defaults.string(forKey: PrefKey.aiBaseURL), "http://localhost:11434/v1")
    }

    /// Someone who only ever configured transcript cleanup still keeps their
    /// provider and model — the feature goes away, the setup doesn't.
    func testFallsBackToOldRewriteConfigWhenNoSelectionConfig() {
        defaults.set("anthropic", forKey: "rewriteProvider")
        defaults.set("claude-haiku-4-5-20251001", forKey: "rewriteModel")

        DefaultPref.migrateLegacyAIConfig(defaults)

        XCTAssertEqual(defaults.string(forKey: PrefKey.aiProvider), "anthropic")
        XCTAssertEqual(defaults.string(forKey: PrefKey.aiModel), "claude-haiku-4-5-20251001")
    }

    /// A fresh install has nothing to carry over and must not invent a value —
    /// writing one here would shadow the registered defaults.
    func testFreshInstallWritesNothing() {
        DefaultPref.migrateLegacyAIConfig(defaults)

        XCTAssertNil(defaults.object(forKey: PrefKey.aiProvider))
        XCTAssertNil(defaults.object(forKey: PrefKey.aiModel))
        XCTAssertNil(defaults.object(forKey: PrefKey.aiBaseURL))
    }

    /// Running twice must not clobber a choice the user made after the first
    /// run — every launch calls this, not just the upgrade launch.
    func testSecondRunLeavesUserChoiceAlone() {
        defaults.set("anthropic", forKey: "selectionRewriteProvider")
        defaults.set("claude-opus-4-8", forKey: "selectionRewriteModel")
        DefaultPref.migrateLegacyAIConfig(defaults)

        // The user then switches to the on-device model.
        defaults.set("appleOnDevice", forKey: PrefKey.aiProvider)
        DefaultPref.migrateLegacyAIConfig(defaults)

        XCTAssertEqual(defaults.string(forKey: PrefKey.aiProvider), "appleOnDevice")
    }

    /// Legacy keys are cleared so a downgrade-then-upgrade can't resurrect a
    /// stale config over the migrated one.
    func testLegacyKeysAreRemoved() {
        defaults.set("anthropic", forKey: "selectionRewriteProvider")
        defaults.set("claude-opus-4-8", forKey: "selectionRewriteModel")
        defaults.set("anthropic", forKey: "rewriteProvider")
        defaults.set(true, forKey: "rewriteEnabled")
        defaults.set("Clean this up: {{input}}", forKey: "rewritePrompt")

        DefaultPref.migrateLegacyAIConfig(defaults)

        XCTAssertFalse(legacyKeysRemain())
    }

    /// A partial legacy config (provider set, model never touched) must not
    /// write an empty model — `aiConfig()` treats empty as "not configured"
    /// and the user would get "No rewrite model configured" out of nowhere.
    func testPartialLegacyConfigLeavesModelToDefaults() {
        defaults.set("anthropic", forKey: "selectionRewriteProvider")

        DefaultPref.migrateLegacyAIConfig(defaults)

        XCTAssertEqual(defaults.string(forKey: PrefKey.aiProvider), "anthropic")
        XCTAssertNil(defaults.object(forKey: PrefKey.aiModel))
    }
}
