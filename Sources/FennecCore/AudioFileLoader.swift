@preconcurrency import AVFoundation
import Foundation

public enum AudioFileLoaderError: Error {
    case unsupportedFormat
    case conversionFailed
}

public enum AudioFileLoader {
    public static let defaultSampleRate: Double = 16000

    public static func loadSamples(
        at url: URL,
        sampleRate: Double = defaultSampleRate
    ) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioFileLoaderError.unsupportedFormat
        }
        try file.read(into: inputBuffer)

        if inputFormat.sampleRate == sampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32,
           let channel = inputBuffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(inputBuffer.frameLength)))
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioFileLoaderError.conversionFailed
        }
        var samples: [Float] = []
        var suppliedInput = false
        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 8192) else {
                throw AudioFileLoaderError.conversionFailed
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                guard !suppliedInput else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }

            if status == .error {
                throw conversionError ?? AudioFileLoaderError.conversionFailed
            }
            if let channel = outputBuffer.floatChannelData?[0], outputBuffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(
                    start: channel,
                    count: Int(outputBuffer.frameLength)
                ))
            }
            if status == .endOfStream || status == .inputRanDry {
                break
            }
        }

        guard !samples.isEmpty else {
            throw AudioFileLoaderError.conversionFailed
        }
        return samples
    }
}
