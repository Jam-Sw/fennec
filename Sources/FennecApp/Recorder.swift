@preconcurrency import AVFoundation
import CoreAudio
import FennecCore
import Foundation

enum RecorderError: Error {
    case formatUnavailable
}

private final class OneShotAudioInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer else { return nil }
        self.buffer = nil
        return buffer
    }
}

/// Owns one `AVAudioEngine` for the app's lifetime instead of building a new
/// one per dictation, so `beginRecording` only ever pays for `engine.start()`
/// - device/route resolution happened once, at `warmUp()`.
final class Recorder: @unchecked Sendable {
    static let sampleRate: Double = 16000

    /// Small enough that the tail-flush wait after key-up stays short
    /// (roughly one buffer's worth of audio at the input's native rate,
    /// typically ~20 ms), instead of the ~93 ms a 4096-frame buffer costs
    /// at 44.1 kHz.
    private static let tapBufferFrames: AVAudioFrameCount = 1024

    /// Serializes engine/tap mutations against the deferred `engine.stop()`
    /// kicked off by `stopEngineDeferred()`, so a fast re-press of the
    /// hotkey can't race a `start()` against a still-in-flight stop.
    private let audioQueue = DispatchQueue(label: "com.fennec.recorder.audio")

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var preRoll: PreRollBuffer
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var running = false

    /// Fired with a short diagnostic line; the caller decides where it goes.
    var onLog: (@Sendable (String) -> Void)?

    init(preRollSeconds: Double) {
        preRoll = PreRollBuffer(capacity: Int(preRollSeconds * Self.sampleRate))
    }

    /// Adjusts pre-roll capacity without touching the engine (e.g. on a
    /// config reload).
    func updatePreRoll(seconds: Double) {
        lock.lock()
        preRoll = PreRollBuffer(capacity: Int(seconds * Self.sampleRate))
        lock.unlock()
    }

    /// Resolves the input route and allocates the engine's render resources
    /// ahead of time. Call once at launch; safe to call again.
    func warmUp() {
        engine.prepare()
        logInputRoute()
    }

    func start() throws {
        lock.lock()
        samples = preRoll.drain()
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ), let audioConverter = AVAudioConverter(from: inputFormat, to: target) else {
            throw RecorderError.formatUnavailable
        }
        converter = audioConverter
        targetFormat = target

        try audioQueue.sync {
            input.installTap(onBus: 0, bufferSize: Self.tapBufferFrames, format: inputFormat) { [weak self] buffer, _ in
                self?.process(buffer)
            }
            if !engine.isRunning {
                try engine.start()
            }
        }
        running = true
    }

    /// Stops capture and returns the samples. Waits briefly for the tap
    /// callback already queued by the hardware at key-up, so the tail of
    /// the last word isn't dropped, then tears the tap down. Does **not**
    /// stop the engine - call `stopEngineDeferred()` for that, once the
    /// caller no longer needs the engine on its critical path.
    func stopCapture() async -> [Float] {
        guard running else { return drainSamples() }
        running = false
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let bufferSeconds = inputFormat.sampleRate > 0
            ? Double(Self.tapBufferFrames) / inputFormat.sampleRate
            : 0.025
        try? await Task.sleep(nanoseconds: UInt64(bufferSeconds * 1_000_000_000))
        return finishSync()
    }

    /// Discards whatever was captured; used when the dictation is cancelled
    /// rather than finished. Synchronous and immediate - no tail flush to
    /// wait on - so a hotkey press right after a cancel can never race the
    /// tap teardown here against `start()` installing a new one.
    func cancel() {
        guard running else { return }
        running = false
        _ = finishSync()
    }

    /// Stops the underlying engine off the caller's critical path. Safe to
    /// call even if a `start()` follows shortly after - `audioQueue`
    /// serializes the two.
    func stopEngineDeferred() {
        audioQueue.async { [engine] in
            if engine.isRunning {
                engine.stop()
            }
        }
    }

    private func finishSync() -> [Float] {
        audioQueue.sync {
            engine.inputNode.removeTap(onBus: 0)
        }
        return drainSamples()
    }

    /// A copy of everything captured so far, leaving capture running. Live
    /// typing transcribes these while the hotkey is still held.
    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// NSLock's `lock()`/`unlock()` can't be called directly from an `async`
    /// function body, so the critical section lives in this synchronous
    /// helper instead.
    private func drainSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples = []
        return result
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }
        var error: NSError?
        let oneShotInput = OneShotAudioInput(buffer)
        converter.convert(to: converted, error: &error) { _, status in
            guard let input = oneShotInput.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return input
        }
        guard error == nil, let channel = converted.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    /// Logs whether the default input is Bluetooth, since HFP route
    /// switching is by far the slowest step in getting the mic live.
    private func logInputRoute() {
        var deviceID = AudioDeviceID(0)
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceIDSize, &deviceID
        )
        guard deviceStatus == noErr else { return }

        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let transportStatus = AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transportType)
        guard transportStatus == noErr else { return }

        let isBluetooth = transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
        onLog?("input route transport=\(isBluetooth ? "bluetooth" : "other") raw=\(transportType)")
    }
}
