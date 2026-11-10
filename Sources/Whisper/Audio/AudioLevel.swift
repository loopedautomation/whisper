import Foundation

/// Loudness measurements over 16 kHz mono samples. Pure functions, so the
/// thresholds the recorder and the pipeline rely on can be tested without a
/// microphone.
enum AudioLevel {
    /// Below this, the loudest moment of a recording is room noise, not speech.
    /// Sending such audio to the model is how "thank you" and subtitle credits
    /// end up pasted into a document.
    static let silenceFloorDB: Float = -50
    /// Above this, the tail of a recording still has someone talking in it.
    static let speechFloorDB: Float = -40

    /// RMS of `samples` in dBFS, with any DC offset removed first (a cheap mic
    /// can sit off-centre and look loud while carrying no sound).
    static func rmsDB(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return -.infinity }
        let mean = samples.reduce(0, +) / Float(samples.count)
        let power = samples.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(samples.count)
        guard power > 0 else { return -.infinity }
        return 10 * log10(power)
    }

    /// The loudest `window`-second stretch of the recording, in dBFS.
    static func loudestWindowDB(_ samples: [Float], sampleRate: Double = AudioRecorder.targetSampleRate,
                                window: Double = 0.03) -> Float {
        let size = max(1, Int(sampleRate * window))
        guard samples.count >= size else { return rmsDB(samples[...]) }
        var loudest = -Float.infinity
        var start = 0
        while start + size <= samples.count {
            loudest = max(loudest, rmsDB(samples[start..<(start + size)]))
            start += size
        }
        return loudest
    }

    /// True when nothing in the recording rises above room noise.
    static func isSilent(_ samples: [Float], sampleRate: Double = AudioRecorder.targetSampleRate) -> Bool {
        loudestWindowDB(samples, sampleRate: sampleRate) < silenceFloorDB
    }

    /// True when the last `window` seconds are quiet: the speaker has finished.
    /// Too little audio to judge counts as not quiet, so the caller keeps going.
    static func tailIsQuiet(_ samples: [Float], sampleRate: Double = AudioRecorder.targetSampleRate,
                            window: Double = 0.16) -> Bool {
        let size = Int(sampleRate * window)
        guard size > 0, samples.count >= size else { return false }
        return rmsDB(samples[(samples.count - size)...]) < speechFloorDB
    }
}
