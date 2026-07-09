import AppKit
import Security

/// Downloads, verifies, and installs an app update in place, then relaunches.
///
/// Safety model: we only ever install a bundle that
///   1. carries a valid, Apple-anchored code signature (Developer ID),
///   2. is signed by the SAME team as the running app, and
///   3. matches our bundle identifier and the advertised version.
/// Dev / ad-hoc builds have no team identifier, so they can never self-update
/// (the UI falls back to linking the releases page instead). All heavy work is
/// blocking — call it off the main actor.
enum UpdateInstaller {
    enum InstallError: LocalizedError {
        case downloadFailed
        case unzipFailed
        case appMissingFromArchive
        case invalidSignature
        case teamMismatch
        case wrongBundle
        case notInstallable

        var errorDescription: String? {
            switch self {
            case .downloadFailed: return "The update could not be downloaded."
            case .unzipFailed: return "The update archive could not be extracted."
            case .appMissingFromArchive: return "The update archive did not contain the app."
            case .invalidSignature: return "The update's code signature is invalid."
            case .teamMismatch: return "The update was not signed by the same developer."
            case .wrongBundle: return "The update is not this application."
            case .notInstallable: return "The app cannot update itself from this location."
            }
        }
    }

    // MARK: - Preflight

    /// True when this running instance can replace itself in place: it is a
    /// real .app bundle in a user-writable location, not Gatekeeper-translocated,
    /// and signed with a team identifier (i.e. a Developer ID release build).
    static func canSelfUpdate(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        guard bundleURL.pathExtension == "app" else { return false }
        guard !isTranslocated(bundleURL) else { return false }
        let fm = FileManager.default
        let parent = bundleURL.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: bundleURL.path),
              fm.isWritableFile(atPath: parent.path) else { return false }
        return runningAppTeamIdentifier() != nil
    }

    /// Gatekeeper app translocation runs the app from a randomized read-only
    /// mount; replacing the original bundle would not affect the running copy.
    static func isTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    // MARK: - Download & stage

    /// Downloads the release zip, extracts it, and verifies the contained app.
    /// Returns the URL of the verified, ready-to-install bundle.
    static func downloadAndStage(zipURL: URL, expectedVersion: String) async throws -> URL {
        var req = URLRequest(url: zipURL)
        req.setValue("LoopedWhisper", forHTTPHeaderField: "User-Agent")
        let (tempFile, response) = try await URLSession.shared.download(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.downloadFailed
        }

        // Stage on the same volume as the installed app so the final swap is
        // a cheap rename rather than a cross-volume copy.
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: Bundle.main.bundleURL, create: true)
        let zip = staging.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: tempFile, to: zip)

        try run("/usr/bin/ditto", "-x", "-k", zip.path, staging.path,
                orThrow: InstallError.unzipFailed)

        let app = staging.appendingPathComponent("LoopedWhisper.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw InstallError.appMissingFromArchive
        }
        try verify(app, expectedVersion: expectedVersion)
        return app
    }

    /// Validates the staged bundle before we let it replace the running app.
    static func verify(_ appURL: URL, expectedVersion: String) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            throw InstallError.invalidSignature
        }

        // Whole-bundle validity with an Apple-anchored chain (Developer ID).
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement)
                == errSecSuccess else {
            throw InstallError.invalidSignature
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw InstallError.invalidSignature
        }

        // Signed by the same team as the running app.
        guard let ours = runningAppTeamIdentifier(),
              teamIdentifier(of: code) == ours else {
            throw InstallError.teamMismatch
        }

        // Sanity: it is this app, at the version we offered.
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              version == expectedVersion else {
            throw InstallError.wrongBundle
        }
    }

    // MARK: - Install & relaunch

    /// Swaps the staged bundle into the running app's location and relaunches.
    /// The old bundle is parked in a system temp directory (never deleted while
    /// we are still executing from its mapped pages).
    static func installAndRelaunch(staged: URL) throws {
        let target = Bundle.main.bundleURL
        guard canSelfUpdate(bundleURL: target) else { throw InstallError.notInstallable }

        // Belt-and-braces: the zip is downloaded by us (no quarantine), but
        // strip the attribute in case a proxy/security tool tagged it.
        try? run("/usr/bin/xattr", "-dr", "com.apple.quarantine", staged.path,
                 orThrow: InstallError.notInstallable)

        let fm = FileManager.default
        let parking = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: target, create: true)
        let oldApp = parking.appendingPathComponent(target.lastPathComponent)
        try fm.moveItem(at: target, to: oldApp)
        do {
            try fm.moveItem(at: staged, to: target)
        } catch {
            try? fm.moveItem(at: oldApp, to: target)   // roll back
            throw error
        }

        // Detached watcher: wait for this process to exit, then open the new
        // copy. The path is passed as $0 so no shell quoting is needed.
        let pid = ProcessInfo.processInfo.processIdentifier
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
            target.path,
        ]
        try relauncher.run()

        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    // MARK: - Helpers

    /// Team identifier of the running app's code signature, or nil for
    /// unsigned / ad-hoc / dev-certificate builds.
    static func runningAppTeamIdentifier() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        return teamIdentifier(of: staticCode)
    }

    private static func teamIdentifier(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func run(_ tool: String, _ arguments: String..., orThrow error: InstallError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw error }
    }
}
