import AppKit
import Combine

/// Checks GitHub Releases for a newer version of the app and, when possible,
/// installs it in place.
///
/// Release builds (Developer ID-signed, installed in a writable location)
/// download the notarized release zip in the background, verify its code
/// signature via `UpdateInstaller`, and offer a one-click "Restart to Update".
/// Anything that can't safely self-update (dev builds, translocated installs,
/// read-only locations, verification failures) falls back to the previous
/// behavior: a link to the releases page. Resilient by design — any network/
/// parsing failure leaves the app in a clean state (no crash, no noisy
/// alerts) and is reflected as `.failed`.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Latest release endpoint for the public repo.
    private static let releasesAPI =
        URL(string: "https://api.github.com/repos/loopedautomation/whisper/releases/latest")!

    /// The repo's releases page — a safe fallback download link.
    static let releasesPage =
        URL(string: "https://github.com/loopedautomation/whisper/releases/latest")!

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        /// A newer release exists but can only be offered as a download link
        /// (no zip asset, or this build can't safely replace itself).
        case updateAvailable(version: String, url: URL)
        /// The update zip is downloading / verifying in the background.
        case downloading(version: String)
        /// A verified copy is staged on disk; restarting installs it.
        case readyToInstall(version: String)
        /// The staged copy is being swapped in; the app restarts on success.
        case installing
        case failed
    }

    @Published private(set) var state: State = .idle

    /// The verified, staged app bundle awaiting install (with its version).
    private var stagedApp: (version: String, url: URL)?
    /// HTML page of the offered release, kept for fallback links.
    private var releasePageURL: URL?

    /// `true` once a newer release has been found (drives the menu/banner UI).
    var hasUpdate: Bool {
        switch state {
        case .updateAvailable, .downloading, .readyToInstall, .installing: return true
        default: return false
        }
    }

    /// Current app version (CFBundleShortVersionString / MARKETING_VERSION).
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Queries the GitHub API, updates `state`, and — when this build can
    /// self-update — downloads and stages the release in the background.
    /// Never throws.
    func check() async {
        switch state {
        case .checking, .downloading, .installing:
            return   // already busy
        default:
            break
        }

        state = .checking
        do {
            var req = URLRequest(url: Self.releasesAPI)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("LoopedWhisper", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .failed
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)

            // Skip drafts / prereleases — only stable releases are offered.
            guard !release.draft, !release.prerelease else {
                state = .upToDate
                return
            }

            let latest = Self.normalize(release.tag_name)
            guard Self.isNewer(latest, than: currentVersion) else {
                state = .upToDate
                return
            }

            let pageURL = release.html_url.flatMap(URL.init(string:)) ?? Self.releasesPage
            releasePageURL = pageURL

            // Already staged and still the latest? Nothing to redo.
            if let staged = stagedApp, staged.version == latest {
                state = .readyToInstall(version: latest)
                return
            }

            let assetNames = (release.assets ?? []).map(\.name)
            if let zipName = Self.preferredZipAsset(named: assetNames, version: latest),
               let zipURL = release.assets?.first(where: { $0.name == zipName })?
                   .browser_download_url.flatMap(URL.init(string:)),
               UpdateInstaller.canSelfUpdate() {
                await stage(version: latest, zipURL: zipURL, pageURL: pageURL)
            } else {
                state = .updateAvailable(version: latest, url: pageURL)
            }
        } catch {
            NSLog("UpdateChecker: check failed: \(error.localizedDescription)")
            state = .failed
        }
    }

    /// Downloads and verifies the release zip; on success the update is staged
    /// and one restart away. On any failure, degrades to the download link.
    private func stage(version: String, zipURL: URL, pageURL: URL) async {
        state = .downloading(version: version)
        do {
            let staged = try await Task.detached(priority: .utility) {
                try await UpdateInstaller.downloadAndStage(zipURL: zipURL, expectedVersion: version)
            }.value
            stagedApp = (version, staged)
            state = .readyToInstall(version: version)
        } catch {
            NSLog("UpdateChecker: staging failed: \(error.localizedDescription)")
            state = .updateAvailable(version: version, url: pageURL)
        }
    }

    /// Swaps the staged bundle into place and relaunches the app. On failure,
    /// degrades to the download link so the user can update manually.
    func installAndRelaunch() {
        guard case .readyToInstall(let version) = state, let staged = stagedApp else { return }
        state = .installing
        let pageURL = releasePageURL ?? Self.releasesPage
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller.installAndRelaunch(staged: staged.url)
                }.value
                // The app terminates and relaunches from here on success.
            } catch {
                NSLog("UpdateChecker: install failed: \(error.localizedDescription)")
                stagedApp = nil
                state = .updateAvailable(version: version, url: pageURL)
            }
        }
    }

    /// Opens the release page in the default browser.
    func openDownloadPage() {
        let url: URL
        if case .updateAvailable(_, let releaseURL) = state {
            url = releaseURL
        } else {
            url = releasePageURL ?? Self.releasesPage
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Release parsing

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]?

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String?
        }
    }

    /// Picks the app zip from a release's asset names: the exact
    /// `LoopedWhisper-<version>.zip` if present, else any LoopedWhisper zip.
    /// DMGs and unrelated assets are never considered.
    static func preferredZipAsset(named names: [String], version: String) -> String? {
        if let exact = names.first(where: { $0 == "LoopedWhisper-\(version).zip" }) {
            return exact
        }
        return names.first { $0.hasPrefix("LoopedWhisper") && $0.hasSuffix(".zip") }
    }

    // MARK: - Version parsing

    /// Strips a leading `v` (e.g. "v0.1.2" → "0.1.2").
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Numeric dotted-component comparison ("0.10.0" > "0.9.0").
    /// Non-numeric / missing components are treated as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate)
        let b = components(current)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let lhs = i < a.count ? a[i] : 0
            let rhs = i < b.count ? b[i] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
