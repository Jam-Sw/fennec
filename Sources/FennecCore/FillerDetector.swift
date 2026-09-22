import Foundation

public protocol FillerDetector: Sendable {
    func fillerRanges(
        samples: [Float],
        sampleRate: Double,
        words: [Word]
    ) async throws -> [Range<TimeInterval>]
}

public struct HeuristicFillerDetector: FillerDetector {
    public var fillers: Set<String>
    public var minPause: TimeInterval

    public init(
        fillers: Set<String> = ["uh", "um", "hmm", "erm"],
        minPause: TimeInterval = Pauses.defaultMinGap
    ) {
        self.fillers = fillers
        self.minPause = minPause
    }

    public func fillerRanges(
        samples: [Float],
        sampleRate: Double,
        words: [Word]
    ) async throws -> [Range<TimeInterval>] {
        let tokens = words.map(\.token)
        var ranges: [Range<TimeInterval>] = []
        for index in words.indices {
            let text = words[index].text
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            guard fillers.contains(text) else { continue }
            guard Pauses.hasPauseBefore(index, in: tokens, minGap: minPause),
                  Pauses.hasPauseAfter(index, in: tokens, minGap: minPause) else { continue }
            ranges.append(words[index].start ..< words[index].end)
        }
        return ranges
    }
}
