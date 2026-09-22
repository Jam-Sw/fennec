import Foundation

public enum TokenRenderer {
    public static func render(_ tokens: [Token]) -> String {
        var output = ""
        var previous: Token?
        for token in tokens {
            if let previous {
                let tight = token.spacing == .ownLine
                    || previous.spacing == .ownLine
                    || token.spacing == .attachBefore
                    || previous.spacing == .attachAfter
                if !tight { output += " " }
            }
            output += token.text
            previous = token
        }
        return output.trimmingCharacters(in: .whitespaces)
    }
}
