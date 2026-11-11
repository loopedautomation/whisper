import Foundation
import AVFoundation
import CoreAudio

/// Captures microphone audio and resamples it to the 16 kHz mono Float32 format
/// Whisper expects. The full buffer is returned on `stop`.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRunning = false
    private var configurationObserver: NSObjectProtocol?

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

        try startEngine()
        isRunning = true
        observeConfigurationChanges()
    }

    /// Points the input node at the chosen device, taps it and starts the
    /// engine. Shared by `start` and by the rebuild after a device change.
    private func startEngine() throws {
        let input = engine.inputNode
        // Route capture to the user-selected input device. When the persisted UID is
        // empty (or the device is gone) we leave the input node on the OS default,
        // which keeps following the system as the user changes inputs.
        applySelectedInputDevice(to: input)
        let inputFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterUnavailable
        }
        lock.lock(); self.converter = converter; lock.unlock()

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
    }

    /// The engine stops itself when its input changes mid-recording (AirPods
    /// connect, a USB mic is unplugged). Rebuild it on the new device and keep
    /// what was captured so far, instead of ending the dictation with half of it.
    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
            do {
                try self.startEngine()
            } catch {
                NSLog("AudioRecorder: couldn't resume after an input change: \(error.localizedDescription)")
            }
        }
    }

    private func stopObservingConfigurationChanges() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
    }

    /// Stops capture and returns the accumulated 16 kHz mono samples.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return [] }
        stopObservingConfigurationChanges()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        lock.lock(); let result = samples; samples.removeAll(); lock.unlock()
        return result
    }

    /// How long capture carries on after the key lifts. People release the key
    /// as they finish the last word, not after it, and stopping on the instant
    /// cuts that word off.
    struct Tail {
        /// Always record at least this much more.
        var minimum: TimeInterval = 0.2
        /// Never more than this, however long the speaker carries on.
        var maximum: TimeInterval = 0.6
        /// Stop once the audio has been this quiet for this long.
        var quiet: TimeInterval = 0.16
    }

    /// Stops like `stop`, after the tail: a short fixed stretch, extended while
    /// speech continues. Returns nil if the recording was stopped by something
    /// else (a cancel) while it waited.
    @MainActor
    func stopAfterTail(_ tail: Tail = Tail()) async -> [Float]? {
        guard isRunning else { return nil }
        let started = Date()
        while isRunning {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= tail.maximum { break }
            if elapsed >= tail.minimum, AudioLevel.tailIsQuiet(snapshot(), window: tail.quiet) { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard isRunning else { return nil }
        return stop()
    }

    /// Current accumulated samples without stopping.
    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    /// Points the engine's input node at the persisted device. A non-empty,
    /// currently-present UID overrides the OS default; otherwise capture follows the
    /// system default input device.
    private func applySelectedInputDevice(to input: AVAudioInputNode) {
        let uid = UserDefaults.standard.string(forKey: PrefKey.inputDeviceUID) ?? ""
        // An explicit choice is honoured. Left on "System Default", a Bluetooth
        // headset is passed over for the built-in mic: opening its microphone
        // drops the headset into call quality for whatever is playing.
        guard let deviceID = AudioInputDevices.deviceID(forUID: uid)
            ?? AudioInputDevices.builtInInsteadOfBluetoothDefault() else { return }

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
        lock.lock(); let converter = self.converter; lock.unlock()
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
