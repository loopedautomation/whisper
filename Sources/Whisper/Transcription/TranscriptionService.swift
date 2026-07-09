import Foundation
import WhisperKit
import ParakeetASR

/// Wraps the transcription engines (WhisperKit and, via speech-swift,
/// Parakeet): lazily loads the selected model and transcribes Float32 16 kHz
/// samples. Models auto-download from Hugging Face on first load and are
/// cached locally, so transcription works fully offline afterwards.
actor TranscriptionService {
    private var pipe: WhisperKit?
    private var parakeet: ParakeetASRModel?
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
        switch WhisperModel.engine(for: model) {
        case .whisperKit:
            if loadedModel == model, pipe != nil { return }
            onProgress?(model)
            let config = WhisperKitConfig(model: model, downloadBase: ModelStorage.baseURL)
            let kit = try await WhisperKit(config)
            pipe = kit
            parakeet = nil
        case .parakeet:
            if loadedModel == model, parakeet != nil { return }
            onProgress?(model)
            let loaded = try await ParakeetASRModel.fromPretrained(
                modelId: model,
                cacheDir: ModelStorage.folder(for: model)
            )
            // First CoreML prediction compiles the graph (~4x latency); do it
            // now on silence so the first real recording is full speed.
            try? loaded.warmUp()
            parakeet = loaded
            pipe = nil
        }
        loadedModel = model
    }

    /// Transcribes the given samples. `vocabulary` biases recognition toward the
    /// listed terms; `selection` decides the language (see `LanguageSelection`).
    func transcribe(samples: [Float], selection: LanguageSelection, vocabulary: [String]) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.empty }

        // Parakeet is natively multilingual (25 European languages) with its
        // own internal language handling — the selection policy and vocabulary
        // biasing are Whisper-specific and don't apply.
        if let parakeet {
            let text = try parakeet.transcribeAudio(samples, sampleRate: Int(AudioRecorder.targetSampleRate))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw TranscriptionError.empty }
            return text
        }

        guard let pipe else { throw TranscriptionError.modelNotLoaded }

        let language: String
        let isOurGuess: Bool   // true only when *we* picked the language, not the user
        switch selection {
        case .auto:
            language = ""
            isOurGuess = false
        case .pinned(let code):
            language = code
            isOurGuess = false
        case .restricted(let candidates):
            // Detect first, then pin the best selected candidate. A detection
            // failure degrades to unrestricted auto-detect instead of failing
            // the whole run.
            language = (try? await detectLanguage(samples: samples, among: candidates)) ?? ""
            isOurGuess = true
        }

        let text = try await decode(samples, language: language, vocabulary: vocabulary, pipe: pipe)
        if !text.isEmpty { return text }

        // A pinned language can occasionally decode to nothing for audio that
        // doesn't actually match it well (e.g. our own detection guessed
        // wrong). Only retry when *we* picked the language — an explicit
        // single-language selection is the user's deliberate choice and isn't
        // second-guessed. One extra decode is cheap insurance against losing
        // an entire recording to one bad guess.
        if isOurGuess, !language.isEmpty {
            let retryText = try await decode(samples, language: "", vocabulary: vocabulary, pipe: pipe)
            guard !retryText.isEmpty else { throw TranscriptionError.empty }
            return retryText
        }
        // A non-empty recording can still decode to nothing (silence, noise, a
        // very short/quiet clip) — treat that the same as "no speech detected"
        // rather than returning "" as if it were a successful transcript, which
        // let the caller play the success chime and skip delivery with no
        // visible warning at all.
        throw TranscriptionError.empty
    }

    private func decode(_ samples: [Float], language: String, vocabulary: [String], pipe: WhisperKit) async throws -> String {
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
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detects the spoken language and returns the best-scoring candidate
    /// among `candidates`.
    func detectLanguage(samples: [Float], among candidates: Set<String>) async throws -> String {
        // Parakeet handles multilingual audio internally — there's no separate
        // detection step. Returning "" makes callers degrade to `.auto`, which
        // the Parakeet transcribe path ignores anyway.
        if parakeet != nil { return "" }
        guard let pipe else { throw TranscriptionError.modelNotLoaded }
        guard !samples.isEmpty else { throw TranscriptionError.empty }
        // [sic] WhisperKit 0.18 spells the array-based variant "detectLangauge".
        let result = try await pipe.detectLangauge(audioArray: samples)
        return WhisperLanguage.pick(detected: result.language, probs: result.langProbs, among: candidates)
    }

    var currentModel: String? { loadedModel }
}
