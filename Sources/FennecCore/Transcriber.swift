import Foundation

public protocol Transcriber: Sendable {
    func prepare(progress: (@Sendable (Double) -> Void)?) async throws
    func isReady() async -> Bool
    func transcribe(samples: [Float], sampleRate: Double) async throws -> Transcript
}

public enum TranscriberError: Error, Equatable {
    case notPrepared
    case emptyResult
    case sampleRateMismatch(expected: Double, got: Double)
}
