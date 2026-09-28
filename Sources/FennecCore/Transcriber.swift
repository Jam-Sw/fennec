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

public extension Transcriber {
    /// Transcribes the samples once and, when the result is empty or
    /// whitespace-only, retries exactly once on the same samples and returns
    /// the second result.
    func transcribeWithRetry(
        samples: [Float],
        sampleRate: Double,
        onRetry: (@Sendable () async -> Void)? = nil
    ) async throws -> Transcript {
        let first = try await transcribe(samples: samples, sampleRate: sampleRate)
        guard first.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return first
        }
        if let onRetry {
            await onRetry()
        }
        return try await transcribe(samples: samples, sampleRate: sampleRate)
    }
}
