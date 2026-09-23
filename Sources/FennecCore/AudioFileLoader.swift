import AVFoundation
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
        let capacity = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * sampleRate / inputFormat.sampleRate
        ) + 512
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioFileLoaderError.conversionFailed
        }

        var conversionError: NSError?
        var suppliedInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
            if suppliedInput {
                outputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outputStatus.pointee = .haveData
            return inputBuffer
        }
        if status == .error {
            throw conversionError ?? AudioFileLoaderError.conversionFailed
        }
        guard let channel = outputBuffer.floatChannelData?[0] else {
            throw AudioFileLoaderError.conversionFailed
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
    }
}
