import XCTest
@testable import Whisper

/// Telemetry is opt-in and promises never to send content. These pin the parts
/// that keep that promise: what goes in a payload, when it may be sent at all,
/// and what a crash report is reduced to.
final class TelemetryTests: XCTestCase {

    /// A throwaway suite so nothing here touches the real user defaults.
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "telemetry-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testNoKeyMeansNoTelemetry() {
        XCTAssertNil(Telemetry.Config(info: nil))
        XCTAssertNil(Telemetry.Config(info: ["PostHogAPIKey": "  "]))
    }

    func testHostDefaultsToPostHogUS() {
        let config = Telemetry.Config(info: ["PostHogAPIKey": "phc_test"])
        XCTAssertEqual(config?.host.absoluteString, "https://us.i.posthog.com")
        let eu = Telemetry.Config(info: ["PostHogAPIKey": "phc_test", "PostHogHost": "https://eu.i.posthog.com"])
        XCTAssertEqual(eu?.host.absoluteString, "https://eu.i.posthog.com")
    }

    /// The test bundle carries no key, so even a "yes" can't send anything.
    func testOffAndUnaskedWithoutAKey() {
        defaults.set(true, forKey: PrefKey.telemetryEnabled)
        XCTAssertFalse(Telemetry.isEnabled(defaults))
        XCTAssertFalse(Telemetry.shouldPrompt(defaults))
    }

    func testPayloadIsAnonymousAndCarriesOnlyWhatWasPassed() {
        let body = Telemetry.payload(.recordingFinished, ["outcome": "empty"],
                                     distinctID: "id-1", apiKey: "phc_test",
                                     date: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(body["event"] as? String, "recording_finished")
        XCTAssertEqual(body["distinct_id"] as? String, "id-1")
        XCTAssertEqual(body["api_key"] as? String, "phc_test")
        let props = body["properties"] as? [String: Any] ?? [:]
        XCTAssertEqual(props["$process_person_profile"] as? Bool, false)
        XCTAssertEqual(props["outcome"] as? String, "empty")
        XCTAssertEqual(Set(props.keys),
                       ["outcome", "app_version", "os_version", "$process_person_profile", "$lib"])
    }

    func testOptingOutDropsTheID() {
        let id = Telemetry.distinctID(defaults)
        XCTAssertEqual(Telemetry.distinctID(defaults), id)
        Telemetry.setEnabled(false, defaults)
        XCTAssertTrue(defaults.bool(forKey: PrefKey.telemetryPrompted))
        XCTAssertNotEqual(Telemetry.distinctID(defaults), id)
    }

    func testCrashSummaryKeepsTypeAndOurFrameButNotTheReason() {
        let log = """
        Looped Whisper Crash Report
        ===========================
        Type:          Uncaught Exception
        Name:          com.apple.coreaudio.avfaudio
        Reason:        something that could quote user data

        Call Stack:
        0   CoreFoundation                      0x000000019b9938fc __exceptionPreprocess   176
        1   LoopedWhisper                       0x0000000102d575a8 $s13LoopedWhisper13CrashReporterO7installyyFZ   460
        2   LoopedWhisper                       0x0000000102d575a8 $s13LoopedWhisper13AudioRecorderC5startyyKF   460
        """
        XCTAssertEqual(CrashReporter.summary(fromLog: log), CrashReporter.Summary(
            kind: "Uncaught Exception",
            name: "com.apple.coreaudio.avfaudio",
            appFrame: "$s13LoopedWhisper13AudioRecorderC5startyyKF"))
    }

    func testCrashSummaryNeedsTypeAndName() {
        XCTAssertNil(CrashReporter.summary(fromLog: "not a crash log"))
    }
}
