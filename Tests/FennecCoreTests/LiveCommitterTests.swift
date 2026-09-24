import Foundation
import Testing
@testable import FennecCore

@Test func liveCommitsOnlyWordsTwoPassesAgreeOn() {
    var live = LiveCommitter(holdback: 1.0)
    let first = [Word(text: "hello", start: 0.1, end: 0.4), Word(text: "word", start: 0.5, end: 0.8)]
    #expect(live.update(words: first, duration: 2.0).isEmpty)

    let second = [
        Word(text: "hello", start: 0.1, end: 0.4),
        Word(text: "world", start: 0.5, end: 0.8),
        Word(text: "again", start: 2.0, end: 2.4),
    ]
    #expect(live.update(words: second, duration: 2.6).map(\.text) == ["hello"])

    let third = second
    #expect(live.update(words: third, duration: 3.2).map(\.text) == ["world"])
    #expect(live.committed.map(\.text) == ["hello", "world"])
}

@Test func liveHoldsBackWordsNearTheEndOfTheAudio() {
    var live = LiveCommitter(holdback: 1.0)
    let words = [Word(text: "hello", start: 0.1, end: 0.4), Word(text: "there", start: 0.6, end: 1.2)]
    live.update(words: words, duration: 1.5)
    #expect(live.update(words: words, duration: 1.8).map(\.text) == ["hello"])
}

@Test func liveAgreementIgnoresCaseAndPunctuation() {
    var live = LiveCommitter(holdback: 0.5)
    live.update(words: [Word(text: "Hello,", start: 0, end: 0.3)], duration: 1)
    #expect(live.update(words: [Word(text: "hello", start: 0, end: 0.3)], duration: 1.2).count == 1)
}

@Test func liveFinalWordsKeepCommittedAndAppendTheTail() {
    var live = LiveCommitter(holdback: 0.5)
    let pass = [Word(text: "one", start: 0, end: 0.3), Word(text: "two", start: 0.4, end: 0.7)]
    live.update(words: pass, duration: 2)
    live.update(words: pass, duration: 2)
    let final = [
        Word(text: "won", start: 0, end: 0.3),
        Word(text: "too", start: 0.42, end: 0.72),
        Word(text: "three", start: 1.0, end: 1.3),
    ]
    #expect(live.finalWords(from: final).map(\.text) == ["one", "two", "three"])
}

@Test func liveDeltaAppendsOrDefers() {
    #expect(LiveTyping.delta(typed: "", rendered: "Hello") == "Hello")
    #expect(LiveTyping.delta(typed: "Hello", rendered: "Hello world.") == " world.")
    #expect(LiveTyping.delta(typed: "Hello world", rendered: "Hello, world") == nil)
}

@Test func configReadsLiveTyping() throws {
    let (config, _) = try Config.decode(Data(#"{"liveTyping": true}"#.utf8))
    #expect(config.liveTyping)
    #expect(Config().liveTyping == false)
}
