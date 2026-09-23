import FennecCore
import Foundation
import Voz

public actor VozTranscriber: Transcriber {
    private var voz: Voz?

    public init() {}

    public func isReady() async -> Bool {
        voz != nil
    }

    public func prepare(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard voz == nil else { return }
        // `Voz.init(progress:)` already downloads-if-missing, verifies, and
        // reports progress (100% immediately when already cached) in one
        // pass. A separate `Voz.isDownloaded()` pre-check here would trigger
        // a second full SHA-256 re-hash of the model files (~466 MB) for the
        // same answer `Voz()` is about to compute anyway.
        let instance = try await Voz(progress: { download in
            progress?(download.fraction)
        })
        voz = instance
    }

    public func transcribe(samples: [Float], sampleRate: Double) async throws -> Transcript {
        guard let voz else { throw TranscriberError.notPrepared }
        guard sampleRate == voz.sampleRate else {
            throw TranscriberError.sampleRateMismatch(expected: voz.sampleRate, got: sampleRate)
        }
        let result = try await voz.transcribe(samples: samples)
        let words = result.words.map {
            FennecCore.Word(text: $0.text, start: $0.start, end: $0.end)
        }
        return FennecCore.Transcript(text: result.text, words: words)
    }

    /// Runs one throwaway transcription so the ANE is woken and its weights
    /// are paged back in before the real transcription request arrives.
    /// Call this at key-down, not launch: a silent buffer trips the
    /// empty-window retry path, so this uses a short synthetic tone instead,
    /// and since `VozTranscriber` is an actor, a real `transcribe` call
    /// issued right after simply queues up behind this one rather than
    /// racing it.
    public func warmUp() async {
        guard let voz else { return }
        let samples = Self.warmUpSamples(sampleRate: voz.sampleRate)
        guard !samples.isEmpty else { return }
        _ = try? await voz.transcribe(samples: samples)
    }

    private static func warmUpSamples(sampleRate: Double) -> [Float] {
        let duration = 0.3
        let frequency = 220.0
        let amplitude: Float = 0.1
        let count = Int(sampleRate * duration)
        guard count > 0 else { return [] }
        return (0 ..< count).map { i in
            Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate)) * amplitude
        }
    }
}
