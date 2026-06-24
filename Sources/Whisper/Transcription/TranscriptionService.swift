import Foundation
import WhisperKit

/// Wraps WhisperKit: lazily loads the selected model and transcribes Float32
/// 16 kHz samples. Models auto-download from Hugging Face on first load and are
/// cached locally, so transcription works fully offline afterwards.
actor TranscriptionService {
    private var pipe: WhisperKit?
    private var loadedModel: String?

    enum TranscriptionError: Error, LocalizedError {
        case empty
        var errorDescription: String? { "No speech detected." }
    }

    /// Ensures the pipeline for `model` is loaded, downloading if needed.
    /// `onProgress` is invoked with a human-readable status while loading.
    func loadModel(_ model: String, onProgress: ((String) -> Void)? = nil) async throws {
        if loadedModel == model, pipe != nil { return }
        onProgress?(model)
        let config = WhisperKitConfig(model: model, downloadBase: ModelStorage.baseURL)
        let kit = try await WhisperKit(config)
        pipe = kit
        loadedModel = model
    }

    /// Transcribes the given samples. `vocabulary` biases recognition toward the
    /// listed terms; `language` is an optional ISO hint ("" = auto-detect).
    func transcribe(samples: [Float], language: String, vocabulary: [String]) async throws -> String {
        guard let pipe else { throw TranscriptionError.empty }
        guard !samples.isEmpty else { throw TranscriptionError.empty }

        var options = DecodingOptions()
        if !language.isEmpty {
            options.language = language
            options.usePrefillPrompt = true
        }
        let prompt = vocabulary.joined(separator: ", ")
        if !prompt.isEmpty {
            options.promptTokens = pipe.tokenizer?.encode(text: " " + prompt)
            options.usePrefillPrompt = true
        }

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentModel: String? { loadedModel }
}
