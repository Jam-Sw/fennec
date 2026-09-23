import Foundation
import Testing
@testable import FennecCore

private actor MockTranscriber: Transcriber {
    private let results: [Transcript]
    private var index = 0

    private(set) var callCount = 0
    private(set) var observedSamples: [[Float]] = []
    private(set) var observedSampleRates: [Double] = []

    init(results: [Transcript]) {
        self.results = results
    }

    func prepare(progress: (@Sendable (Double) -> Void)?) async throws {}

    func isReady() async -> Bool { true }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> Transcript {
        callCount += 1
        observedSamples.append(samples)
        observedSampleRates.append(sampleRate)

        let result: Transcript
        if results.isEmpty {
            result = Transcript(text: "", words: [])
        } else {
            result = results[min(index, results.count - 1)]
        }
        index += 1
        return result
    }
}

private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@Test func retriesExactlyOnceWhenFirstResultIsEmpty() async throws {
    let mock = MockTranscriber(results: [
        Transcript(text: "", words: []),
        Transcript(text: "hello", words: [Word(text: "hello", start: 0, end: 0.5)]),
    ])

    let transcript = try await mock.transcribeWithRetry(samples: [1.0, 2.0, 3.0], sampleRate: 16000)

    #expect(transcript.text == "hello")
    #expect(transcript.words == [Word(text: "hello", start: 0, end: 0.5)])
    let callCount = await mock.callCount
    #expect(callCount == 2)
}

@Test func retriesWhenFirstResultIsWhitespaceOnly() async throws {
    let mock = MockTranscriber(results: [
        Transcript(text: " \n\t ", words: []),
        Transcript(text: "hello", words: [Word(text: "hello", start: 0, end: 0.5)]),
    ])

    let transcript = try await mock.transcribeWithRetry(samples: [1.0], sampleRate: 16000)

    #expect(transcript.text == "hello")
    let callCount = await mock.callCount
    #expect(callCount == 2)
}

@Test func returnsFirstResultWithoutRetryWhenItHasText() async throws {
    let mock = MockTranscriber(results: [
        Transcript(text: "hello", words: [Word(text: "hello", start: 0, end: 0.5)]),
    ])

    let transcript = try await mock.transcribeWithRetry(samples: [1.0], sampleRate: 16000)

    #expect(transcript.text == "hello")
    let callCount = await mock.callCount
    #expect(callCount == 1)
}

@Test func retriesExactlyOnceAndReturnsSecondResultEvenWhenStillEmpty() async throws {
    let mock = MockTranscriber(results: [
        Transcript(text: "", words: []),
        Transcript(text: "", words: []),
    ])

    let transcript = try await mock.transcribeWithRetry(samples: [1.0], sampleRate: 16000)

    #expect(transcript.text.isEmpty)
    let callCount = await mock.callCount
    #expect(callCount == 2)
}

@Test func forwardsTheSameSamplesAndSampleRateOnEveryCall() async throws {
    let samples: [Float] = [0.1, 0.2, 0.3]
    let mock = MockTranscriber(results: [
        Transcript(text: "", words: []),
        Transcript(text: "hello", words: []),
    ])

    _ = try await mock.transcribeWithRetry(samples: samples, sampleRate: 44_100)

    let observedSamples = await mock.observedSamples
    let observedSampleRates = await mock.observedSampleRates
    #expect(observedSamples == [samples, samples])
    #expect(observedSampleRates == [44_100, 44_100])
}

@Test func onRetryFiresOnlyWhenRetrying() async throws {
    let retryCounter = CallCounter()
    let retryMock = MockTranscriber(results: [
        Transcript(text: "", words: []),
        Transcript(text: "hello", words: []),
    ])
    _ = try await retryMock.transcribeWithRetry(
        samples: [1.0],
        sampleRate: 16000,
        onRetry: { await retryCounter.increment() }
    )
    #expect(await retryCounter.value == 1)
    #expect(await retryMock.callCount == 2)

    let noRetryCounter = CallCounter()
    let noRetryMock = MockTranscriber(results: [
        Transcript(text: "hello", words: []),
    ])
    _ = try await noRetryMock.transcribeWithRetry(
        samples: [1.0],
        sampleRate: 16000,
        onRetry: { await noRetryCounter.increment() }
    )
    #expect(await noRetryCounter.value == 0)
    #expect(await noRetryMock.callCount == 1)
}
