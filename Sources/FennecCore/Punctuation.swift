import Foundation

public struct PunctuationRule: Equatable, Sendable {
    public var replacement: String
    public var spacing: TokenSpacing

    public init(replacement: String, spacing: TokenSpacing) {
        self.replacement = replacement
        self.spacing = spacing
    }
}

public enum Punctuation {
    public static let defaultRules: [String: PunctuationRule] = [
        "period": PunctuationRule(replacement: ".", spacing: .attachBefore),
        "full stop": PunctuationRule(replacement: ".", spacing: .attachBefore),
        "comma": PunctuationRule(replacement: ",", spacing: .attachBefore),
        "question mark": PunctuationRule(replacement: "?", spacing: .attachBefore),
        "exclamation mark": PunctuationRule(replacement: "!", spacing: .attachBefore),
        "exclamation point": PunctuationRule(replacement: "!", spacing: .attachBefore),
        "colon": PunctuationRule(replacement: ":", spacing: .attachBefore),
        "semicolon": PunctuationRule(replacement: ";", spacing: .attachBefore),
        "new line": PunctuationRule(replacement: "\n", spacing: .ownLine),
        "new paragraph": PunctuationRule(replacement: "\n\n", spacing: .ownLine),
        "open paren": PunctuationRule(replacement: "(", spacing: .attachAfter),
        "open parenthesis": PunctuationRule(replacement: "(", spacing: .attachAfter),
        "close paren": PunctuationRule(replacement: ")", spacing: .attachBefore),
        "close parenthesis": PunctuationRule(replacement: ")", spacing: .attachBefore),
        "dash": PunctuationRule(replacement: "-", spacing: .normal),
        "hyphen": PunctuationRule(replacement: "-", spacing: .normal),
    ]

    public static func rules(overrides: [String: String]) -> [String: PunctuationRule] {
        var rules = defaultRules
        for (command, replacement) in overrides {
            let key = command.lowercased()
            if let existing = rules[key] {
                rules[key] = PunctuationRule(replacement: replacement, spacing: existing.spacing)
            } else {
                rules[key] = PunctuationRule(replacement: replacement, spacing: .normal)
            }
        }
        return rules
    }

    public static func apply(
        to tokens: [Token],
        rules: [String: PunctuationRule] = defaultRules,
        minPause: TimeInterval = Pauses.defaultMinGap
    ) -> [Token] {
        let maxWindow = rules.keys
            .map { $0.split(separator: " ").count }
            .max() ?? 1
        var result: [Token] = []
        var index = 0
        while index < tokens.count {
            var matched = false
            let window = min(maxWindow, tokens.count - index)
            for size in stride(from: window, through: 1, by: -1) {
                let slice = Array(tokens[index ..< index + size])
                let phrase = slice.map { $0.cleanedText.lowercased() }.joined(separator: " ")
                guard let rule = rules[phrase] else { continue }
                let contiguous = zip(slice, slice.dropFirst())
                    .allSatisfy { $1.start - $0.end < minPause }
                guard contiguous else { continue }
                guard Pauses.hasPauseBefore(index, in: tokens, minGap: minPause),
                      Pauses.hasPauseAfter(index + size - 1, in: tokens, minGap: minPause) else { continue }
                result.append(Token(
                    text: rule.replacement,
                    start: slice.first?.start ?? 0,
                    end: slice.last?.end ?? 0,
                    isProtected: true,
                    spacing: rule.spacing
                ))
                index += size
                matched = true
                break
            }
            if !matched {
                result.append(tokens[index])
                index += 1
            }
        }
        return result
    }
}
