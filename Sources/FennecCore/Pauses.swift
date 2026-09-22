import Foundation

public enum Pauses {
    public static let defaultMinGap: TimeInterval = 0.25

    public static func hasPauseBefore(
        _ index: Int,
        in tokens: [Token],
        minGap: TimeInterval = defaultMinGap
    ) -> Bool {
        guard index > 0 else { return true }
        return tokens[index].start - tokens[index - 1].end >= minGap
    }

    public static func hasPauseAfter(
        _ index: Int,
        in tokens: [Token],
        minGap: TimeInterval = defaultMinGap
    ) -> Bool {
        guard index < tokens.count - 1 else { return true }
        return tokens[index + 1].start - tokens[index].end >= minGap
    }
}
