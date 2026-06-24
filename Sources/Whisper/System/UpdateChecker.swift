import AppKit
import Combine

/// Checks GitHub Releases for a newer version of the app.
///
/// Distribution is via GitHub Releases + a Homebrew cask, so there is no
/// silent self-replacing updater: we notify the user when a newer release
/// exists and link them to the download page. Resilient by design — any
/// network/parsing failure leaves the app in a clean state (no crash, no
/// noisy alerts) and is reflected as `.failed`.
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
        /// A newer release is available, with its version string and HTML page URL.
        case updateAvailable(version: String, url: URL)
        case failed
    }

    @Published private(set) var state: State = .idle

    /// `true` once a newer release has been found (drives the menu/banner UI).
    var hasUpdate: Bool {
        if case .updateAvailable = state { return true }
        return false
    }

    /// Current app version (CFBundleShortVersionString / MARKETING_VERSION).
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Queries the GitHub API and updates `state`. Never throws.
    func check() async {
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
            if Self.isNewer(latest, than: currentVersion) {
                let url = release.html_url.flatMap(URL.init(string:)) ?? Self.releasesPage
                state = .updateAvailable(version: latest, url: url)
            } else {
                state = .upToDate
            }
        } catch {
            NSLog("UpdateChecker: check failed: \(error.localizedDescription)")
            state = .failed
        }
    }

    /// Opens the release page in the default browser.
    func openDownloadPage() {
        let url: URL
        if case .updateAvailable(_, let releaseURL) = state {
            url = releaseURL
        } else {
            url = Self.releasesPage
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Version parsing

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String?
        let draft: Bool
        let prerelease: Bool
    }

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
