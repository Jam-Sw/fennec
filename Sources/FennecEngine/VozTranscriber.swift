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
        if !Voz.isDownloaded() {
            _ = try await Voz.download { download in
                progress?(download.fraction)
            }
        }
        let instance = try await Voz()
        voz = instance
        // No warm-up pass: a silent buffer trips the empty-window retry path,
        // and the ANE compile cache is warm after the first real transcription.
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
}
