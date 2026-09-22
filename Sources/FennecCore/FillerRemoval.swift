import Foundation

public enum FillerRemoval {
    public static func remove(tokens: [Token], overlapping spans: [Range<TimeInterval>]) -> [Token] {
        guard !spans.isEmpty else { return tokens }
        return tokens.filter { token in
            !spans.contains { span in
                token.start < span.upperBound && span.lowerBound < token.end
            }
        }
    }
}
