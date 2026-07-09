import Foundation
import AppKit

/// Executes a matched quick action. Dictated text only ever fills the
/// `{{query}}` placeholder (percent-encoded for URLs); the action target
/// itself is user-entered at configuration time, and subprocess arguments are
/// always passed as arrays — never through a shell.
enum QuickActionExecutor {
    struct ExecutionError: Error {
        var message: String
        var hint: String?
    }

    static func execute(_ action: QuickAction, query: String?) -> Result<Void, ExecutionError> {
        switch action.kind {
        case .openURL:
            return resolveURL(action, query: query).map { NSWorkspace.shared.open($0) }
        case .openURLIncognito:
            return resolveURL(action, query: query).flatMap(openIncognito)
        case .launchApp:
            return launchApp(named: substitute(action.target, query: query, encodeForURL: false))
        case .quitApp:
            return quitApp(named: substitute(action.target, query: query, encodeForURL: false))
        case .runShortcut:
            return runShortcut(named: substitute(action.target, query: query, encodeForURL: false))
        }
    }

    // MARK: - target interpolation

    static func substitute(_ target: String, query: String?, encodeForURL: Bool) -> String {
        guard target.contains("{{query}}") else { return target }
        var q = query ?? ""
        if encodeForURL {
            q = q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        }
        return target.replacingOccurrences(of: "{{query}}", with: q)
    }

    /// Prepends `https://` to schemeless targets ("github.com" works).
    static func normalizeURLString(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("://") { return s }
        return "https://" + s
    }

    private static func resolveURL(_ action: QuickAction, query: String?) -> Result<URL, ExecutionError> {
        let str = normalizeURLString(substitute(action.target, query: query, encodeForURL: true))
        guard let url = URL(string: str), url.host != nil else {
            return .failure(ExecutionError(
                message: "\"\(action.name)\" has an invalid URL",
                hint: "check its target in Settings → Actions"))
        }
        return .success(url)
    }

    // MARK: - incognito

    /// Private-window flag per browser. Safari has no CLI flag — its private
    /// windows need AppleScript (Automation permission), so we fall back to a
    /// normal window rather than dragging in that entitlement.
    private static let privateFlags: [String: String] = [
        "com.google.chrome": "--incognito",
        "com.google.chrome.canary": "--incognito",
        "com.brave.browser": "--incognito",
        "com.vivaldi.vivaldi": "--incognito",
        "com.microsoft.edgemac": "--inprivate",
        "org.mozilla.firefox": "--private-window"
    ]

    private static func openIncognito(_ url: URL) -> Result<Void, ExecutionError> {
        guard let browserURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let bundleID = Bundle(url: browserURL)?.bundleIdentifier?.lowercased(),
              let flag = privateFlags[bundleID] else {
            // Unknown browser or Safari: open normally rather than failing.
            NSWorkspace.shared.open(url)
            return .success(())
        }
        // `open -na <Browser> --args <flag> <url>` starts a new private window
        // without needing Apple Events / Automation permission.
        return run("/usr/bin/open", ["-na", browserURL.path, "--args", flag, url.absoluteString])
    }

    // MARK: - apps & shortcuts

    private static func launchApp(named name: String) -> Result<Void, ExecutionError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ExecutionError(message: "No app name configured"))
        }
        // `open -a` resolves by display name, activates if already running.
        return run("/usr/bin/open", ["-a", trimmed]).mapError { _ in
            ExecutionError(message: "Couldn't open \"\(trimmed)\"",
                           hint: "check the app name in Settings → Actions")
        }
    }

    /// Asks the app to quit gracefully (same as Cmd+Q — the app may prompt to
    /// save); never force-kills.
    private static func quitApp(named name: String) -> Result<Void, ExecutionError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ExecutionError(message: "No app name configured"))
        }
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.caseInsensitiveCompare(trimmed) == .orderedSame
                || $0.bundleIdentifier?.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !running.isEmpty else {
            return .failure(ExecutionError(message: "\"\(trimmed)\" isn't running"))
        }
        running.forEach { $0.terminate() }
        return .success(())
    }

    private static func runShortcut(named name: String) -> Result<Void, ExecutionError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(ExecutionError(message: "No Shortcut name configured"))
        }
        // Fire and forget — shortcuts can run long; failures are logged.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", trimmed]
        let stderr = Pipe()
        p.standardError = stderr
        p.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                NSLog("Shortcut \"\(trimmed)\" failed: \(msg)")
            }
        }
        do {
            try p.run()
            return .success(())
        } catch {
            return .failure(ExecutionError(message: "Couldn't run Shortcut \"\(trimmed)\"",
                                           hint: error.localizedDescription))
        }
    }

    private static func run(_ path: String, _ arguments: [String]) -> Result<Void, ExecutionError> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                return .failure(ExecutionError(message: "Command failed (\(p.terminationStatus))"))
            }
            return .success(())
        } catch {
            return .failure(ExecutionError(message: "Couldn't run command", hint: error.localizedDescription))
        }
    }
}
