import Foundation
import AppKit
import WhisperKit
import ParakeetASR

/// Which library runs a given model. WhisperKit serves the openai/whisper
/// family; speech-swift serves additional architectures (currently Parakeet).
enum TranscriptionEngine: String, Hashable {
    case whisperKit
    case parakeet
}

/// Catalog of the models the app can fetch. WhisperKit models come from the
/// `argmaxinc/whisperkit-coreml` Hugging Face repo; Parakeet from its own
/// CoreML repo via speech-swift. This is the "bring your own model" surface —
/// the user picks one and it is downloaded + cached on first use.
struct WhisperModel: Identifiable, Hashable {
    let id: String      // engine-specific model identifier
    let label: String   // human label
    let note: String    // size / speed hint
    var engine: TranscriptionEngine = .whisperKit

    static let known: [WhisperModel] = [
        .init(id: "tiny",   label: "Tiny",   note: "~75 MB · fastest, least accurate"),
        .init(id: "base",   label: "Base",   note: "~145 MB · fast, good default"),
        .init(id: "small",  label: "Small",  note: "~470 MB · balanced"),
        .init(id: "medium", label: "Medium", note: "~1.5 GB · accurate, slower"),
        .init(id: "large-v3", label: "Large v3", note: "~3 GB · most accurate"),
        .init(id: "large-v3-v20240930", label: "Large v3 (turbo)", note: "~1.5 GB · fast + accurate"),
        .init(id: ModelStorage.parakeetRepo, label: "Parakeet v3",
              note: "~600 MB · 25 European languages, fast · auto-detects language",
              engine: .parakeet)
    ]

    static func label(for id: String) -> String {
        known.first(where: { $0.id == id })?.label ?? id
    }

    static func engine(for id: String) -> TranscriptionEngine {
        known.first(where: { $0.id == id })?.engine ?? .whisperKit
    }
}

/// Single source of truth for where models live on disk. WhisperKit downloads
/// into `<base>/models/<repo>/openai_whisper-<variant>` via HubApi; Parakeet
/// into `<base>/models/<repo>` via speech-swift's `cacheDir` override.
enum ModelStorage {
    static let repo = "argmaxinc/whisperkit-coreml"
    static let parakeetRepo = "aufklarer/Parakeet-TDT-v3-CoreML-INT8-30s"

    /// Root we hand to WhisperKit as `downloadBase`. Shared between release and
    /// dev builds so models aren't downloaded twice.
    static let baseURL: URL = AppPaths.sharedModels

    static func folder(for modelID: String) -> URL {
        switch WhisperModel.engine(for: modelID) {
        case .whisperKit:
            return baseURL
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(repo, isDirectory: true)
                .appendingPathComponent("openai_whisper-\(modelID)", isDirectory: true)
        case .parakeet:
            return baseURL
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(modelID, isDirectory: true)
        }
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

    /// Removes a downloaded model's files from disk and flips its state back to
    /// `.notDownloaded`. Cancels any in-flight download for the same id first.
    /// Returns `false` (leaving a `.failed` state) if the files couldn't be removed.
    @discardableResult
    func delete(_ id: String) -> Bool {
        cancelDownload(id)
        let folder = ModelStorage.folder(for: id)
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            states[id] = .notDownloaded
            return true
        } catch {
            states[id] = .failed("Couldn’t delete: \(error.localizedDescription)")
            return false
        }
    }

    private func performDownload(_ id: String) async -> Bool {
        states[id] = .downloading(0)
        defer { downloadTasks[id] = nil }
        do {
            try Task.checkCancellation()
            switch WhisperModel.engine(for: id) {
            case .whisperKit:
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
            case .parakeet:
                // fromPretrained both downloads and loads; here we only care
                // about the download side — the loaded instance is discarded
                // and TranscriptionService loads its own from the same cache.
                _ = try await ParakeetASRModel.fromPretrained(
                    modelId: id,
                    cacheDir: ModelStorage.folder(for: id),
                    progressHandler: { fraction, _ in
                        Task { @MainActor in
                            if case .downloading = self.states[id] {
                                self.states[id] = .downloading(fraction)
                            }
                        }
                    }
                )
            }
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
