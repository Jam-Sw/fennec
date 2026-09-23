@preconcurrency import AVFoundation
import FennecCore
import Foundation

enum RecorderError: Error {
    case formatUnavailable
}

final class Recorder: @unchecked Sendable {
    static let sampleRate: Double = 16000

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var running = false

    init(preRollSeconds: Double) {
        _ = preRollSeconds
    }

    func start() throws {
        lock.lock()
        samples = []
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

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() -> [Float] {
        finish()
    }

    func cancel() {
        _ = finish()
    }

    private func finish() -> [Float] {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
        }
        lock.lock()
        let result = samples
        samples = []
        lock.unlock()
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
        var supplied = false
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = converted.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }
}
