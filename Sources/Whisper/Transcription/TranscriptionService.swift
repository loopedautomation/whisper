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
        case modelNotLoaded
        var errorDescription: String? {
            switch self {
            case .empty: return "No speech detected."
            case .modelNotLoaded: return "Transcription model isn't loaded yet."
            }
        }
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
    /// listed terms; `selection` decides the language (see `LanguageSelection`).
    func transcribe(samples: [Float], selection: LanguageSelection, vocabulary: [String]) async throws -> String {
        guard let pipe else { throw TranscriptionError.modelNotLoaded }
        guard !samples.isEmpty else { throw TranscriptionError.empty }

        let language: String
        switch selection {
        case .auto:
            language = ""
        case .pinned(let code):
            language = code
        case .restricted(let candidates):
            // Detect first, then pin the best selected candidate. A detection
            // failure degrades to unrestricted auto-detect instead of failing
            // the whole run.
            language = (try? await detectLanguage(samples: samples, among: candidates)) ?? ""
        }

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

    /// Detects the spoken language and returns the best-scoring candidate
    /// among `candidates`.
    func detectLanguage(samples: [Float], among candidates: Set<String>) async throws -> String {
        guard let pipe else { throw TranscriptionError.modelNotLoaded }
        guard !samples.isEmpty else { throw TranscriptionError.empty }
        // [sic] WhisperKit 0.18 spells the array-based variant "detectLangauge".
        let result = try await pipe.detectLangauge(audioArray: samples)
        return WhisperLanguage.pick(detected: result.language, probs: result.langProbs, among: candidates)
    }

    var currentModel: String? { loadedModel }
}
