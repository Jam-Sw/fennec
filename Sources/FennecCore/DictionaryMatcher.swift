import Foundation

public struct DictionaryMatch: Equatable, Sendable {
    public var range: Range<Int>
    public var canonical: String

    public init(range: Range<Int>, canonical: String) {
        self.range = range
        self.canonical = canonical
    }
}

public enum DictionaryMatcher {
    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    public static func matches(
        in tokens: [Token],
        dictionary: TermDictionary,
        maxGap: TimeInterval = 0.4,
        maxWindow: Int = 5
    ) -> [DictionaryMatch] {
        var lookup: [String: String] = [:]
        for entry in dictionary.entries {
            for alias in entry.aliases {
                lookup[normalize(alias)] = entry.canonical
            }
        }

        var result: [DictionaryMatch] = []
        var index = 0
        while index < tokens.count {
            var matched = false
            let window = min(maxWindow, tokens.count - index)
            for size in stride(from: window, through: 1, by: -1) {
                let slice = Array(tokens[index ..< index + size])
                if size > 1 {
                    let contiguous = zip(slice, slice.dropFirst())
                        .allSatisfy { $1.start - $0.end < maxGap }
                    guard contiguous else { continue }
                }
                let key = normalize(slice.map(\.text).joined())
                guard let canonical = lookup[key] else { continue }
                result.append(DictionaryMatch(range: index ..< (index + size), canonical: canonical))
                index += size
                matched = true
                break
            }
            if !matched { index += 1 }
        }
        return result
    }

    public static func apply(_ matches: [DictionaryMatch], to tokens: [Token]) -> [Token] {
        guard !matches.isEmpty else { return tokens }
        var output: [Token] = []
        var cursor = 0
        for match in matches {
            if cursor < match.range.lowerBound {
                output.append(contentsOf: tokens[cursor ..< match.range.lowerBound])
            }
            let slice = tokens[match.range]
            output.append(Token(
                text: match.canonical,
                start: slice.first?.start ?? 0,
                end: slice.last?.end ?? 0,
                isProtected: true
            ))
            cursor = match.range.upperBound
        }
        if cursor < tokens.count {
            output.append(contentsOf: tokens[cursor...])
        }
        return output
    }
}
