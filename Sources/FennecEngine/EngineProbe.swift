import Foundation
import Voz

/// Minimal end-to-end check: file in, transcript out. Replaced by VozTranscriber in Task 8.
public enum EngineProbe {
    public static func transcribeFile(at url: URL) async throws -> String {
        let voz = try await Voz()
        let result = try await voz.transcribe(url)
        return result.text
    }
}
