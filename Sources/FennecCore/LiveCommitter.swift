import Foundation

/// Decides which words from repeated passes over a growing recording are
/// settled enough to type while the hotkey is still held.
///
/// Voz is an offline recogniser, so live typing re-transcribes the whole
/// buffer every so often. The newest words change from pass to pass as more
/// context arrives, and typed text cannot be taken back, so a word is only
/// committed once two consecutive passes agree on it and it ends at least
/// `holdback` seconds before the end of the audio.
public struct LiveCommitter: Sendable {
    public private(set) var committed: [Word] = []
    private var pending: [Word] = []
    private let holdback: TimeInterval

    public init(holdback: TimeInterval = 1.0) {
        self.holdback = holdback
    }

    /// Where the committed words stop, in seconds from the start of the audio.
    public var committedEnd: TimeInterval {
        committed.last?.end ?? 0
    }

    /// Feeds one pass over the first `duration` seconds of audio and returns
    /// the words newly committed by it.
    @discardableResult
    public mutating func update(words: [Word], duration: TimeInterval) -> [Word] {
        let tail = uncommitted(words)
        var agreed = 0
        while agreed < tail.count, agreed < pending.count,
              Self.normalized(tail[agreed].text) == Self.normalized(pending[agreed].text),
              tail[agreed].end <= duration - holdback {
            agreed += 1
        }
        let fresh = Array(tail.prefix(agreed))
        committed += fresh
        pending = Array(tail.dropFirst(agreed))
        return fresh
    }

    /// The whole dictation: the committed words, then whatever the final pass
    /// heard after them.
    public func finalWords(from words: [Word]) -> [Word] {
        committed + uncommitted(words)
    }

    /// Words from a pass that fall after the committed ones. A word counts as
    /// after when its midpoint is, which tolerates the small timestamp drift
    /// between passes.
    private func uncommitted(_ words: [Word]) -> [Word] {
        guard !committed.isEmpty else { return words }
        let boundary = committedEnd
        return words.filter { ($0.start + $0.end) / 2 >= boundary }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

public enum LiveTyping {
    /// The text still to type so the screen reads `rendered`, or nil when
    /// `rendered` no longer starts with what was typed. A later word can
    /// change earlier rendering (a punctuation command, a dictionary phrase),
    /// and typed text is not taken back, so the caller waits for the final
    /// pass instead.
    public static func delta(typed: String, rendered: String) -> String? {
        guard rendered.hasPrefix(typed) else { return nil }
        return String(rendered.dropFirst(typed.count))
    }
}
