import Foundation

/// Opt-in, anonymous usage telemetry, sent to PostHog.
///
/// Off until the user says yes — in the prompt shown once after install, or in
/// Settings → About — and it can be turned off there again at any time. What
/// can be sent is fixed by `Event` and the properties passed at each call
/// site: launches, whether model loads and recordings worked, crash types, and
/// the app/macOS version and selected model. Never transcripts, selections,
/// vocabulary, app names, file paths or error messages (which can contain any
/// of those).
///
/// Builds without a PostHog key (forks, local builds) can't send anything and
/// never ask.
enum Telemetry {

    enum Event: String {
        case telemetryEnabled = "telemetry_enabled"
        case appLaunched = "app_launched"
        case modelLoaded = "model_loaded"
        case modelLoadFailed = "model_load_failed"
        case recordingStartFailed = "recording_start_failed"
        case recordingFinished = "recording_finished"
        case crashDetected = "crash_detected"
    }

    struct Config: Equatable {
        let apiKey: String
        let host: URL

        /// `scripts/build-app.sh` writes these into Info.plist from the
        /// `POSTHOG_API_KEY` / `POSTHOG_HOST` environment variables.
        init?(info: [String: Any]?) {
            let key = (info?["PostHogAPIKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            let host = (info?["PostHogHost"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: host.isEmpty ? "https://us.i.posthog.com" : host) else { return nil }
            apiKey = key
            self.host = url
        }
    }

    static let config = Config(info: Bundle.main.infoDictionary)

    static var isAvailable: Bool { config != nil }

    static func isEnabled(_ d: UserDefaults = .standard) -> Bool {
        isAvailable && d.bool(forKey: PrefKey.telemetryEnabled)
    }

    /// True until the user has answered the prompt, either way.
    static func shouldPrompt(_ d: UserDefaults = .standard) -> Bool {
        isAvailable && !d.bool(forKey: PrefKey.telemetryPrompted)
    }

    static func setEnabled(_ on: Bool, _ d: UserDefaults = .standard) {
        d.set(true, forKey: PrefKey.telemetryPrompted)
        d.set(on, forKey: PrefKey.telemetryEnabled)
        if on {
            capture(.telemetryEnabled)
        } else {
            // Turning it back on later starts a new id, unlinked from this one.
            d.removeObject(forKey: PrefKey.telemetryDistinctID)
        }
    }

    static func capture(_ event: Event, _ properties: [String: Any] = [:]) {
        guard isEnabled(), let config else { return }
        let body = payload(event, properties, distinctID: distinctID(), apiKey: config.apiKey, date: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: config.host.appendingPathComponent("capture/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 10
        // Fire and forget: losing an event is fine, a retry queue isn't worth it.
        URLSession.shared.dataTask(with: request).resume()
    }

    /// The exact JSON body sent for one event.
    static func payload(_ event: Event, _ properties: [String: Any], distinctID: String,
                        apiKey: String, date: Date) -> [String: Any] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var props: [String: Any] = [
            "app_version": CrashReporter.appVersion,
            "os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            // Anonymous events only: no PostHog person profile is created.
            "$process_person_profile": false,
            "$lib": "looped-whisper"
        ]
        props.merge(properties) { _, new in new }
        return [
            "api_key": apiKey,
            "event": event.rawValue,
            "distinct_id": distinctID,
            "timestamp": ISO8601DateFormatter().string(from: date),
            "properties": props
        ]
    }

    /// A random id made only for telemetry, so one install's events can be
    /// grouped without saying whose install it is.
    static func distinctID(_ d: UserDefaults = .standard) -> String {
        if let id = d.string(forKey: PrefKey.telemetryDistinctID) { return id }
        let id = UUID().uuidString
        d.set(id, forKey: PrefKey.telemetryDistinctID)
        return id
    }

    /// Sends the type of each crash captured on an earlier run, once per log.
    /// Only the crash kind, name and the app function it happened in — the
    /// full log stays on disk for the user to share or not.
    static func reportNewCrashes(_ d: UserDefaults = .standard) {
        guard isEnabled(d) else { return }
        var reported = Set(d.stringArray(forKey: PrefKey.telemetryReportedCrashes) ?? [])
        for url in CrashReporter.pendingLogs() where !reported.contains(url.lastPathComponent) {
            guard let summary = CrashReporter.summary(of: url) else { continue }
            var props: [String: Any] = ["kind": summary.kind, "name": summary.name]
            if let frame = summary.appFrame { props["app_frame"] = frame }
            capture(.crashDetected, props)
            reported.insert(url.lastPathComponent)
        }
        d.set(Array(reported), forKey: PrefKey.telemetryReportedCrashes)
    }
}
