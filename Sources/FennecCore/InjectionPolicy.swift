import Foundation

public enum InjectionOutcome: Equatable, Sendable {
    case paste(autoSend: Bool)
    case clipboardOnly(reason: InjectionBlockReason)
}

public enum InjectionBlockReason: Equatable, Sendable {
    case noSpeech
    case focusChanged
    case secureInput
}

public enum InjectionPolicy {
    public static func decide(
        hasText: Bool,
        focusChanged: Bool,
        secureInput: Bool,
        autoSend: Bool
    ) -> InjectionOutcome {
        if !hasText { return .clipboardOnly(reason: .noSpeech) }
        if secureInput { return .clipboardOnly(reason: .secureInput) }
        if focusChanged { return .clipboardOnly(reason: .focusChanged) }
        return .paste(autoSend: autoSend)
    }
}
