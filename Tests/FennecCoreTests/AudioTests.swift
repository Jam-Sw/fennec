import Foundation
import Testing
@testable import FennecCore

@Test func silenceTrimsToEmpty() {
    let silence = [Float](repeating: 0, count: 16000)
    #expect(SilenceTrimmer.trim(silence, sampleRate: 16000).isEmpty)
}

@Test func leadingAndTrailingSilenceAreTrimmed() {
    var samples = [Float](repeating: 0, count: 8000)
    samples += [Float](repeating: 0.5, count: 16000)
    samples += [Float](repeating: 0, count: 8000)
    let trimmed = SilenceTrimmer.trim(samples, sampleRate: 16000)
    #expect(trimmed.count >= 16000)
    #expect(trimmed.count <= 17600)
    #expect(trimmed.contains(0.5))
}

@Test func interiorSilenceIsKept() {
    var samples = [Float](repeating: 0.5, count: 8000)
    samples += [Float](repeating: 0, count: 8000)
    samples += [Float](repeating: 0.5, count: 8000)
    let trimmed = SilenceTrimmer.trim(samples, sampleRate: 16000, pad: 0)
    #expect(trimmed.count == 24000)
}

@Test func preRollKeepsOnlyTheNewestSamples() {
    var buffer = PreRollBuffer(capacity: 4)
    buffer.append([1, 2, 3])
    #expect(buffer.drain() == [1, 2, 3])
    buffer.append([1, 2, 3, 4, 5])
    #expect(buffer.drain() == [2, 3, 4, 5])
    #expect(buffer.drain().isEmpty)
}

@Test func preRollWithZeroCapacityIsEmpty() {
    var buffer = PreRollBuffer(capacity: 0)
    buffer.append([1, 2, 3])
    #expect(buffer.drain().isEmpty)
}
