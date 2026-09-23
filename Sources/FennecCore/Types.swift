import Foundation

public struct Word: Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }

    public var token: Token {
        Token(text: text, start: start, end: end)
    }
}

public struct Transcript: Equatable, Sendable {
    public var text: String
    public var words: [Word]

    public init(text: String, words: [Word]) {
        self.text = text
        self.words = words
    }
}

public enum TokenSpacing: Equatable, Sendable {
    case normal
    case attachBefore
    case attachAfter
    case ownLine
}

public struct Token: Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var isProtected: Bool
    public var spacing: TokenSpacing

    public init(
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        isProtected: Bool = false,
        spacing: TokenSpacing = .normal
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.isProtected = isProtected
        self.spacing = spacing
    }
}

public extension Token {
    /// The token text with edge punctuation removed, for matching against
    /// dictionaries and spoken commands. Voz attaches sentence punctuation to words.
    var cleanedText: String {
        text.trimmingCharacters(in: .punctuationCharacters)
    }
}
