import Foundation

public enum Capitalization {
    public static func apply(to tokens: [Token]) -> [Token] {
        var result = tokens
        var capitalizeNext = true
        for index in result.indices {
            let token = result[index]
            if token.spacing == .ownLine {
                capitalizeNext = true
                continue
            }
            let endsSentence = token.text.hasSuffix(".")
                || token.text.hasSuffix("!")
                || token.text.hasSuffix("?")
            if capitalizeNext,
               !token.isProtected,
               let first = token.text.first,
               first.isLetter,
               first.isLowercase {
                result[index].text = token.text.prefix(1).uppercased() + token.text.dropFirst()
            }
            capitalizeNext = endsSentence
        }
        return result
    }
}
