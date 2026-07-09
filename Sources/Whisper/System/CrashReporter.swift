import Foundation
import AppKit

/// Lightweight, privacy-respecting **local** crash reporting.
///
/// On install, `CrashReporter` registers an uncaught-exception handler and a set
/// of POSIX signal handlers. When the app crashes, it captures a small text log
/// (exception/signal name, reason, call-stack symbols, app version, macOS version,
/// timestamp) and writes it to a `CrashLogs` directory under Application Support.
///
/// **Nothing is ever sent anywhere automatically.** On the next launch, the app
/// detects any saved logs and surfaces them to the user, who is fully in control
/// of whether to view, copy, delete, or file a GitHub issue with the contents.
///
/// macOS itself also records richer crash reports under
/// `~/Library/Logs/DiagnosticReports`; ``CrashReporter`` points users there too.
enum CrashReporter {

    // MARK: - Locations

    /// ~/Library/Application Support/Looped Whisper/CrashLogs
    static var directory: URL {
        let dir = AppPaths.support.appendingPathComponent("CrashLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Where macOS stores its own (more detailed) crash reports.
    static var diagnosticReportsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
    }

    // MARK: - Install

    private static var didInstall = false

    /// Installs the uncaught-exception and signal handlers. Safe to call once at
    /// startup; subsequent calls are no-ops.
    static func install() {
        guard !didInstall else { return }
        didInstall = true

        NSSetUncaughtExceptionHandler { exception in
            let log = CrashReporter.makeLog(
                kind: "Uncaught Exception",
                name: exception.name.rawValue,
                reason: exception.reason ?? "(no reason)",
                symbols: exception.callStackSymbols
            )
            CrashReporter.write(log)
        }

        for sig in handledSignals {
            signal(sig) { received in
                // Signal-handler context: keep work minimal and async-signal-tolerant.
                // We accept that Foundation calls here are technically unsafe, but in
                // practice this captures useful local diagnostics. After writing, we
                // restore the default handler and re-raise so the OS still produces
                // its own (authoritative) crash report in DiagnosticReports.
                let log = CrashReporter.makeLog(
                    kind: "Signal",
                    name: CrashReporter.name(forSignal: received),
                    reason: "Fatal signal \(received) received",
                    symbols: Thread.callStackSymbols
                )
                CrashReporter.write(log)
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }

    private static let handledSignals: [Int32] = [SIGABRT, SIGSEGV, SIGILL, SIGBUS, SIGFPE]

    private static func name(forSignal sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGILL:  return "SIGILL"
        case SIGBUS:  return "SIGBUS"
        case SIGFPE:  return "SIGFPE"
        default:      return "SIG\(sig)"
        }
    }

    // MARK: - Capture

    private static func makeLog(kind: String, name: String, reason: String, symbols: [String]) -> String {
        var lines: [String] = []
        lines.append("Looped Whisper Crash Report")
        lines.append("===========================")
        lines.append("Date:          \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("App Version:   \(appVersion)")
        lines.append("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Type:          \(kind)")
        lines.append("Name:          \(name)")
        lines.append("Reason:        \(reason)")
        lines.append("")
        lines.append("Call Stack:")
        lines.append(contentsOf: symbols)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static func write(_ contents: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        let url = directory.appendingPathComponent("crash-\(stamp).log")
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Surfacing prior crashes

    /// All crash logs we captured, newest first.
    static func pendingLogs() -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }
    }

    static func hasPendingLogs() -> Bool { !pendingLogs().isEmpty }

    static func clearLogs() {
        for url in pendingLogs() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(pendingLogs())
    }

    static func revealDiagnosticReports() {
        NSWorkspace.shared.open(diagnosticReportsDirectory)
    }

    /// Combined text of the most recent crash log, suitable for the clipboard or
    /// a GitHub issue body.
    static func mostRecentLogContents() -> String? {
        guard let url = pendingLogs().first else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Builds a prefilled "new issue" URL for the public repo. The crash log is
    /// included in the body, truncated to keep the URL within practical limits.
    static func githubIssueURL() -> URL? {
        var components = URLComponents(string: "https://github.com/loopedautomation/whisper/issues/new")
        var body = "**Describe what you were doing when the app crashed:**\n\n\n"
        body += "**Crash log:**\n\n```\n"
        if let log = mostRecentLogContents() {
            // Keep the URL reasonable; the user can attach the full log if needed.
            body += String(log.prefix(4000))
        }
        body += "\n```\n"
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Crash report: Looped Whisper \(appVersion)"),
            URLQueryItem(name: "labels", value: "crash"),
            URLQueryItem(name: "body", value: body),
        ]
        return components?.url
    }
}
