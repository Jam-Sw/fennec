import Foundation
import Testing
@testable import FennecCore

@Test func rendererAppliesSpacingRules() {
    let tokens = [
        Token(text: "hello", start: 0, end: 0.3),
        Token(text: ",", start: 0.4, end: 0.4, isProtected: true, spacing: .attachBefore),
        Token(text: "world", start: 0.5, end: 0.8),
        Token(text: "\n", start: 1.2, end: 1.2, isProtected: true, spacing: .ownLine),
        Token(text: "(", start: 1.3, end: 1.3, isProtected: true, spacing: .attachAfter),
        Token(text: "again", start: 1.4, end: 1.8),
        Token(text: ")", start: 1.9, end: 1.9, isProtected: true, spacing: .attachBefore),
    ]
    #expect(TokenRenderer.render(tokens) == "hello, world\n(again)")
}

@Test func capitalizationAtStartAndAfterSentence() {
    let tokens = [
        Token(text: "hello", start: 0, end: 0.3),
        Token(text: "there", start: 0.35, end: 0.6),
        Token(text: ".", start: 0.7, end: 0.7, isProtected: true, spacing: .attachBefore),
        Token(text: "next", start: 0.8, end: 1.0),
    ]
    #expect(Capitalization.apply(to: tokens).map(\.text) == ["Hello", "there", ".", "Next"])
}

@Test func protectedTokensKeepCanonicalCasing() {
    let tokens = [
        Token(text: "claude", start: 0, end: 0.3),
        Token(text: "code", start: 0.35, end: 0.7),
    ]
    let matches = [DictionaryMatch(range: 0 ..< 2, canonical: "Claude Code")]
    let applied = DictionaryMatcher.apply(matches, to: tokens)
    #expect(Capitalization.apply(to: applied).map(\.text) == ["Claude Code"])
}

@Test func fullPipelineEndToEnd() {
    let words = [
        Word(text: "open", start: 0.0, end: 0.3),
        Word(text: "code", start: 0.35, end: 0.65),
        Word(text: "is", start: 0.7, end: 0.85),
        Word(text: "ready", start: 0.9, end: 1.2),
        Word(text: "uh", start: 1.7, end: 1.9),
        Word(text: "new", start: 2.3, end: 2.5),
        Word(text: "line", start: 2.55, end: 2.8),
        Word(text: "k", start: 3.3, end: 3.4),
        Word(text: "c", start: 3.45, end: 3.55),
        Word(text: "g", start: 3.6, end: 3.7),
        Word(text: "event", start: 3.75, end: 4.05),
        Word(text: "tap", start: 4.1, end: 4.35),
    ]
    let text = TextPipeline.process(
        words: words,
        config: PipelineConfig(),
        dictionary: .builtIn,
        fillerSpans: [1.7 ..< 1.9]
    )
    #expect(text == "opencode is ready\nkCGEventTap")
}

@Test func disabledStagesKeepRawText() {
    let words = [
        Word(text: "hello", start: 0.0, end: 0.3),
        Word(text: "open", start: 0.9, end: 1.1),
        Word(text: "code", start: 1.15, end: 1.4),
    ]
    let config = PipelineConfig(fillerRemoval: false, punctuation: false, capitalization: false)
    let text = TextPipeline.process(
        words: words,
        config: config,
        dictionary: TermDictionary(entries: []),
        fillerSpans: []
    )
    #expect(text == "hello open code")
}
