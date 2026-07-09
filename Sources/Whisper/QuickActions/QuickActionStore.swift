import Foundation
import AppKit
import Combine

/// User-managed list of voice quick actions, persisted as JSON at
/// `~/Library/Application Support/Looped Whisper/quick-actions.json`.
/// The file can be hand-edited; the list reloads when the Actions settings
/// tab appears.
@MainActor
final class QuickActionStore: ObservableObject {
    @Published private(set) var actions: [QuickAction] = []

    let fileURL = AppPaths.quickActionsFile

    init() {
        load()
        seedExamplesIfNeeded()
    }

    func add(_ action: QuickAction) {
        actions.append(action)
        save()
    }

    func update(_ action: QuickAction) {
        guard let i = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[i] = action
        save()
    }

    func remove(_ action: QuickAction) {
        actions.removeAll { $0.id == action.id }
        save()
    }

    func setEnabled(_ action: QuickAction, _ enabled: Bool) {
        guard let i = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[i].enabled = enabled
        save()
    }

    /// Re-reads the file from disk (picks up external hand-edits).
    func reload() { load() }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: - persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([QuickAction].self, from: data) else { return }
        actions = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(actions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Seed a few disabled examples on first launch so the Actions tab shows
    /// what's possible instead of an empty list.
    private func seedExamplesIfNeeded() {
        guard actions.isEmpty, !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        actions = [
            QuickAction(name: "Open GitHub", triggers: ["take me to github", "open github"],
                        kind: .openURL, target: "https://github.com", enabled: false),
            QuickAction(name: "Web search", triggers: ["search for"],
                        kind: .openURL, target: "https://www.google.com/search?q={{query}}", enabled: false),
            QuickAction(name: "Open Notes", triggers: ["open notes"],
                        kind: .launchApp, target: "Notes", enabled: false)
        ]
        save()
    }
}
