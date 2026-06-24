import Foundation
import AVFoundation
import CoreAudio

/// Captures microphone audio and resamples it to the 16 kHz mono Float32 format
/// Whisper expects. Used for batch mode (the full buffer is returned on `stop`).
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRunning = false

    /// Whisper's required input format.
    static let targetSampleRate: Double = 16_000

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioRecorder.targetSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    enum RecorderError: Error, LocalizedError {
        case converterUnavailable
        case engineStartFailed(String)
        var errorDescription: String? {
            switch self {
            case .converterUnavailable: return "Could not create audio converter."
            case .engineStartFailed(let m): return "Audio engine failed: \(m)"
            }
        }
    }

    func start() throws {
        guard !isRunning else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        // Route capture to the user-selected input device. When the persisted UID is
        // empty (or the device is gone) we leave the input node on the OS default,
        // which keeps following the system as the user changes inputs.
        applySelectedInputDevice(to: input)
        let inputFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterUnavailable
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineStartFailed(error.localizedDescription)
        }
        isRunning = true
    }

    /// Stops capture and returns the accumulated 16 kHz mono samples.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        lock.lock(); let result = samples; samples.removeAll(); lock.unlock()
        return result
    }

    /// Current accumulated samples without stopping (used by realtime mode).
    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    /// Points the engine's input node at the persisted device. A non-empty,
    /// currently-present UID overrides the OS default; otherwise capture follows the
    /// system default input device.
    private func applySelectedInputDevice(to input: AVAudioInputNode) {
        let uid = UserDefaults.standard.string(forKey: PrefKey.inputDeviceUID) ?? ""
        guard let deviceID = AudioInputDevices.deviceID(forUID: uid) else { return }

        // The input node is backed by an HAL audio unit; setting its current device
        // reroutes capture without rebuilding the engine.
        guard let unit = input.audioUnit else { return }
        var device = deviceID
        AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func append(buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let statusResult = converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        guard statusResult != .error, let channel = outBuffer.floatChannelData else { return }

        let frames = Int(outBuffer.frameLength)
        guard frames > 0 else { return }
        let ptr = channel[0]
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: frames))
        lock.unlock()
    }
}
