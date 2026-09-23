import Foundation
import Testing
@testable import FennecCore

@Test func parsesEntriesCommentsAndAliases() {
    let text = """
    # dev terms
    kubectl = cube control, cube cuddle
    opencode

    tmux
    """
    let dictionary = TermDictionary.parse(text)
    #expect(dictionary.entries.count == 3)
    #expect(dictionary.entries[0].canonical == "kubectl")
    #expect(dictionary.entries[0].aliases == ["kubectl", "cube control", "cube cuddle"])
    #expect(dictionary.entries[1].aliases == ["opencode"])
}

@Test func multiwordAliasMatchesAndApplyProtects() {
    let words = [
        Word(text: "open", start: 0, end: 0.3),
        Word(text: "code", start: 0.35, end: 0.7),
    ]
    let tokens = words.map(\.token)
    let matches = DictionaryMatcher.matches(in: tokens, dictionary: .builtIn)
    #expect(matches.count == 1)
    #expect(matches[0].canonical == "opencode")
    let applied = DictionaryMatcher.apply(matches, to: tokens)
    #expect(applied.map(\.text) == ["opencode"])
    #expect(applied[0].isProtected)
    #expect(applied[0].start == 0)
    #expect(applied[0].end == 0.7)
}

@Test func gapBreaksMatch() {
    let words = [
        Word(text: "open", start: 0, end: 0.3),
        Word(text: "code", start: 0.9, end: 1.3),
    ]
    let matches = DictionaryMatcher.matches(in: words.map(\.token), dictionary: .builtIn)
    #expect(matches.isEmpty)
}

@Test func longestMatchWins() {
    let dictionary = TermDictionary(entries: [
        DictionaryEntry(canonical: "code"),
        DictionaryEntry(canonical: "opencode", aliases: ["open code"]),
    ])
    let words = [
        Word(text: "open", start: 0, end: 0.3),
        Word(text: "code", start: 0.35, end: 0.7),
    ]
    let matches = DictionaryMatcher.matches(in: words.map(\.token), dictionary: dictionary)
    #expect(matches.count == 1)
    #expect(matches[0].canonical == "opencode")
}

@Test func partialWordIsNotMatched() {
    let words = [Word(text: "opencodes", start: 0, end: 0.5)]
    let matches = DictionaryMatcher.matches(in: words.map(\.token), dictionary: .builtIn)
    #expect(matches.isEmpty)
}

@Test func missingFileFallsBackToBuiltIn() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let dictionary = try TermDictionary.load(from: url)
    #expect(dictionary.entries.count == TermDictionary.builtIn.entries.count)
}

@Test func matchesTokensCarryingAsrPunctuation() {
    let words = [
        Word(text: "Send", start: 0, end: 0.3),
        Word(text: "open", start: 0.35, end: 0.6),
        Word(text: "code.", start: 0.65, end: 0.95),
    ]
    let tokens = words.map(\.token)
    let matches = DictionaryMatcher.matches(in: tokens, dictionary: .builtIn)
    #expect(matches.count == 1)
    #expect(matches[0].canonical == "opencode")
    let applied = DictionaryMatcher.apply(matches, to: tokens)
    #expect(applied.map(\.text) == ["Send", "opencode."])
}

@Test func builtInSurvivesSerializeAndParse() {
    let text = TermDictionary.builtIn.serialized()
    #expect(text.contains("kubectl = cube control, cube cuddle\n"))
    #expect(TermDictionary.parse(text) == TermDictionary.builtIn)
}
