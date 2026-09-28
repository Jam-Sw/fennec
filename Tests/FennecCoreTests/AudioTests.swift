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

private let fixturesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

// The fixtures are gitignored and made locally by scripts/make-fixtures.sh
// (hello.* comes from `say`, whose output depends on the installed voice),
// so these tests only run where that script has been run.
private func fixture(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: fixturesRoot.appendingPathComponent("fixtures/\(name)").path)
}

@Test(.enabled(if: fixture("hello.wav"), "run scripts/make-fixtures.sh"))
func audioFileLoaderLoads16KilohertzWave() throws {
    let samples = try AudioFileLoader.loadSamples(at: fixturesRoot.appendingPathComponent("fixtures/hello.wav"))
    #expect(samples.count == 81652)
    #expect(samples.contains { $0 != 0 })
}

@Test(.enabled(if: fixture("hello.aiff"), "run scripts/make-fixtures.sh"))
func audioFileLoaderResamplesAiffTo16Kilohertz() throws {
    let samples = try AudioFileLoader.loadSamples(at: fixturesRoot.appendingPathComponent("fixtures/hello.aiff"))
    #expect(!samples.isEmpty)
    #expect(abs(samples.count - 81652) <= 64)
    #expect(samples.contains { abs($0) > 0.01 })
}

@Test(.enabled(if: fixture("silence.wav"), "run scripts/make-fixtures.sh"))
func audioFileLoaderLoadsSilence() throws {
    let samples = try AudioFileLoader.loadSamples(at: fixturesRoot.appendingPathComponent("fixtures/silence.wav"))
    #expect(samples.count == 32000)
    #expect(samples.allSatisfy { abs($0) < 0.01 })
}
