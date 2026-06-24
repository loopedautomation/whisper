import Foundation
import AppKit
import WhisperKit

/// Catalog of the open Whisper models WhisperKit can fetch from the
/// `argmaxinc/whisperkit-coreml` Hugging Face repo. This is the "bring your own
/// model" surface — the user picks one and it is downloaded + cached on first use.
struct WhisperModel: Identifiable, Hashable {
    let id: String      // WhisperKit model identifier
    let label: String   // human label
    let note: String    // size / speed hint

    static let known: [WhisperModel] = [
        .init(id: "tiny",   label: "Tiny",   note: "~75 MB · fastest, least accurate"),
        .init(id: "base",   label: "Base",   note: "~145 MB · fast, good default"),
        .init(id: "small",  label: "Small",  note: "~470 MB · balanced"),
        .init(id: "medium", label: "Medium", note: "~1.5 GB · accurate, slower"),
        .init(id: "large-v3", label: "Large v3", note: "~3 GB · most accurate"),
        .init(id: "large-v3-v20240930", label: "Large v3 (turbo)", note: "~1.5 GB · fast + accurate")
    ]

    static func label(for id: String) -> String {
        known.first(where: { $0.id == id })?.label ?? id
    }
}

/// Single source of truth for where models live on disk. WhisperKit downloads
/// into `<base>/models/<repo>/openai_whisper-<variant>` via HubApi.
enum ModelStorage {
    static let repo = "argmaxinc/whisperkit-coreml"

    /// Root we hand to WhisperKit as `downloadBase` so the location is deterministic.
    static let baseURL: URL = {
        let dir = AppPaths.support.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func folder(for modelID: String) -> URL {
        baseURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(repo, isDirectory: true)
            .appendingPathComponent("openai_whisper-\(modelID)", isDirectory: true)
    }
}

/// Tracks per-model download state and drives downloads with live progress.
@MainActor
final class ModelManager: ObservableObject {
    enum State: Equatable {
        case downloaded
        case notDownloaded
        case downloading(Double)  // 0...1
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]
    private var downloadTasks: [String: Task<Bool, Never>] = [:]

    var baseURL: URL { ModelStorage.baseURL }

    init() { refreshAll() }

    func state(for id: String) -> State {
        states[id] ?? .notDownloaded
    }

    func isDownloaded(_ id: String) -> Bool {
        let folder = ModelStorage.folder(for: id)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return !contents.isEmpty
    }

    func refreshAll() {
        for model in WhisperModel.known {
            // Don't clobber an in-flight download.
            if case .downloading = states[model.id] { continue }
            states[model.id] = isDownloaded(model.id) ? .downloaded : .notDownloaded
        }
    }

    func folderPath(for id: String) -> String {
        ModelStorage.folder(for: id).path
    }

    /// Starts (or returns the in-flight) download task for a model.
    @discardableResult
    func startDownload(_ id: String) -> Task<Bool, Never> {
        if let existing = downloadTasks[id] { return existing }
        let task = Task { await self.performDownload(id) }
        downloadTasks[id] = task
        return task
    }

    /// Awaitable download (used by the coordinator when loading a model).
    @discardableResult
    func download(_ id: String) async -> Bool {
        await startDownload(id).value
    }

    /// Cancels an in-flight download and reverts the row to its prior state.
    func cancelDownload(_ id: String) {
        downloadTasks[id]?.cancel()
        downloadTasks[id] = nil
        states[id] = isDownloaded(id) ? .downloaded : .notDownloaded
    }

    private func performDownload(_ id: String) async -> Bool {
        states[id] = .downloading(0)
        defer { downloadTasks[id] = nil }
        do {
            try Task.checkCancellation()
            _ = try await WhisperKit.download(
                variant: id,
                downloadBase: ModelStorage.baseURL,
                from: ModelStorage.repo,
                progressCallback: { progress in
                    Task { @MainActor in
                        if case .downloading = self.states[id] {
                            self.states[id] = .downloading(progress.fractionCompleted)
                        }
                    }
                }
            )
            try Task.checkCancellation()
            states[id] = .downloaded
            return true
        } catch is CancellationError {
            states[id] = isDownloaded(id) ? .downloaded : .notDownloaded
            return false
        } catch {
            states[id] = .failed(error.localizedDescription)
            return false
        }
    }

    func revealInFinder(_ id: String) {
        let folder = ModelStorage.folder(for: id)
        let target = isDownloaded(id) ? folder : ModelStorage.baseURL
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func revealBaseInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([ModelStorage.baseURL])
    }
}
