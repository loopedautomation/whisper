import XCTest
@testable import Whisper

/// Updating from a version with more settings than this one must leave a
/// working app: retired settings go, everything the user chose stays.
final class SettingsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "settings-migration-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testOldInstallLosesRetiredSettingsAndKeepsTheRest() {
        // An install from before realtime mode was removed.
        defaults.set("realtime", forKey: "transcriptionMode")
        defaults.set("incremental", forKey: "realtimeInsertion")
        defaults.set(true, forKey: "restoreClipboard")
        defaults.set(true, forKey: "telemetryEnabled")
        defaults.set("3F2A", forKey: "telemetryDistinctID")
        defaults.set("large-v3", forKey: PrefKey.selectedModel)
        defaults.set(true, forKey: PrefKey.fnEnabled)
        defaults.set("copyOnly", forKey: PrefKey.outputBehavior)
        defaults.set(0.4, forKey: PrefKey.soundVolume)

        DefaultPref.migrateRetiredSettings(defaults)

        for key in DefaultPref.retiredKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should be gone")
        }
        XCTAssertEqual(defaults.string(forKey: PrefKey.selectedModel), "large-v3")
        XCTAssertTrue(defaults.bool(forKey: PrefKey.fnEnabled))
        XCTAssertEqual(defaults.string(forKey: PrefKey.outputBehavior), "copyOnly")
        XCTAssertEqual(defaults.double(forKey: PrefKey.soundVolume), 0.4)
        XCTAssertEqual(defaults.integer(forKey: DefaultPref.settingsVersionKey), DefaultPref.settingsVersion)
    }

    func testFreshInstallIsStampedAndOtherwiseUntouched() {
        DefaultPref.migrateRetiredSettings(defaults)
        XCTAssertEqual(defaults.integer(forKey: DefaultPref.settingsVersionKey), DefaultPref.settingsVersion)
        XCTAssertNil(defaults.object(forKey: PrefKey.selectedModel))
    }

    /// Once migrated, a later launch must not strip a key again: a future
    /// version may give one of these names a new meaning.
    func testRunsOnlyOnce() {
        DefaultPref.migrateRetiredSettings(defaults)
        defaults.set("batch", forKey: "transcriptionMode")
        DefaultPref.migrateRetiredSettings(defaults)
        XCTAssertEqual(defaults.string(forKey: "transcriptionMode"), "batch")
    }
}
