import Foundation
import Testing
@testable import FennecCore

@Test func periodInsidePhraseIsKept() {
    let words = [
        Word(text: "for", start: 0.0, end: 0.3),
        Word(text: "a", start: 0.35, end: 0.5),
        Word(text: "period", start: 0.55, end: 0.95),
        Word(text: "of", start: 1.0, end: 1.2),
        Word(text: "time", start: 1.3, end: 1.7),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["for", "a", "period", "of", "time"])
}

@Test func standaloneTrailingPeriodBecomesSymbol() {
    let words = [
        Word(text: "ship", start: 0.0, end: 0.4),
        Word(text: "it", start: 0.45, end: 0.7),
        Word(text: "period", start: 1.2, end: 1.7),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["ship", "it", "."])
    #expect(tokens.last?.spacing == .attachBefore)
}

@Test func isolatedCommaBetweenWordsBecomesSymbol() {
    let words = [
        Word(text: "first", start: 0.0, end: 0.4),
        Word(text: "comma", start: 0.9, end: 1.2),
        Word(text: "second", start: 1.7, end: 2.0),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["first", ",", "second"])
}

@Test func commaInsideSentenceStaysAWord() {
    let words = [
        Word(text: "add", start: 0.0, end: 0.3),
        Word(text: "a", start: 0.35, end: 0.5),
        Word(text: "comma", start: 0.55, end: 0.9),
        Word(text: "here", start: 0.95, end: 1.2),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["add", "a", "comma", "here"])
}

@Test func multiwordNewLineCommand() {
    let words = [
        Word(text: "done", start: 0.0, end: 0.4),
        Word(text: "new", start: 0.9, end: 1.1),
        Word(text: "line", start: 1.15, end: 1.4),
        Word(text: "next", start: 1.8, end: 2.1),
    ]
    let tokens = Punctuation.apply(to: words.map(\.token))
    #expect(tokens.map(\.text) == ["done", "\n", "next"])
    #expect(tokens[1].spacing == .ownLine)
}

@Test func overridesReplaceKnownAndAddNew() {
    let rules = Punctuation.rules(overrides: ["period": "!", "tick": "`"])
    #expect(rules["period"]?.replacement == "!")
    #expect(rules["period"]?.spacing == .attachBefore)
    #expect(rules["tick"]?.replacement == "`")
    #expect(rules["tick"]?.spacing == .normal)
}
