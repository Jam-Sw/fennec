import Foundation

public struct PipelineConfig: Equatable, Sendable {
    public var fillerRemoval: Bool
    public var punctuation: Bool
    public var capitalization: Bool
    public var punctuationRules: [String: PunctuationRule]

    public init(
        fillerRemoval: Bool = true,
        punctuation: Bool = true,
        capitalization: Bool = true,
        punctuationRules: [String: PunctuationRule] = Punctuation.defaultRules
    ) {
        self.fillerRemoval = fillerRemoval
        self.punctuation = punctuation
        self.capitalization = capitalization
        self.punctuationRules = punctuationRules
    }

    public static func from(_ config: Config) -> PipelineConfig {
        PipelineConfig(
            fillerRemoval: config.fillerRemoval,
            punctuation: config.punctuation,
            capitalization: config.capitalization,
            punctuationRules: Punctuation.rules(overrides: config.punctuationCommands)
        )
    }
}

public enum TextPipeline {
    public static func process(
        words: [Word],
        config: PipelineConfig,
        dictionary: TermDictionary,
        fillerSpans: [Range<TimeInterval>]
    ) -> String {
        var tokens = words.map(\.token)
        if config.fillerRemoval {
            tokens = FillerRemoval.remove(tokens: tokens, overlapping: fillerSpans)
        }
        let matches = DictionaryMatcher.matches(in: tokens, dictionary: dictionary)
        tokens = DictionaryMatcher.apply(matches, to: tokens)
        if config.punctuation {
            tokens = Punctuation.apply(to: tokens, rules: config.punctuationRules)
        }
        if config.capitalization {
            tokens = Capitalization.apply(to: tokens)
        }
        return TokenRenderer.render(tokens)
    }
}
