import Foundation
import Testing
@testable import FennecCore

@Test func isolatedFillerIsDetected() async throws {
    let words = [
        Word(text: "send", start: 0.0, end: 0.4),
        Word(text: "it", start: 0.45, end: 0.7),
        Word(text: "uh", start: 1.2, end: 1.5),
    ]
    let ranges = try await HeuristicFillerDetector().fillerRanges(samples: [], sampleRate: 16000, words: words)
    #expect(ranges == [1.2 ..< 1.5])
}

@Test func fillerInsideAPhraseIsKept() async throws {
    let words = [
        Word(text: "this", start: 0.0, end: 0.3),
        Word(text: "is", start: 0.35, end: 0.5),
        Word(text: "uh", start: 0.55, end: 0.8),
        Word(text: "fine", start: 0.85, end: 1.1),
    ]
    let ranges = try await HeuristicFillerDetector().fillerRanges(samples: [], sampleRate: 16000, words: words)
    #expect(ranges.isEmpty)
}

@Test func leadingFillerIsDetected() async throws {
    let words = [
        Word(text: "um", start: 0.0, end: 0.3),
        Word(text: "deploy", start: 0.8, end: 1.2),
    ]
    let ranges = try await HeuristicFillerDetector().fillerRanges(samples: [], sampleRate: 16000, words: words)
    #expect(ranges == [0.0 ..< 0.3])
}

@Test func removalDropsOverlappingTokens() {
    let tokens = [
        Token(text: "send", start: 0.0, end: 0.4),
        Token(text: "uh", start: 0.9, end: 1.2),
        Token(text: "now", start: 1.7, end: 2.0),
    ]
    let result = FillerRemoval.remove(tokens: tokens, overlapping: [0.9 ..< 1.2])
    #expect(result.map(\.text) == ["send", "now"])
}

@Test func customFillerSetIsHonored() async throws {
    let words = [
        Word(text: "like", start: 0.0, end: 0.3),
        Word(text: "go", start: 0.8, end: 1.0),
    ]
    let ranges = try await HeuristicFillerDetector(fillers: ["like"]).fillerRanges(samples: [], sampleRate: 16000, words: words)
    #expect(ranges == [0.0 ..< 0.3])
}
