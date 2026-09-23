import Foundation

public struct HotkeyStateMachine: Sendable {
    public enum Event: Equatable, Sendable {
        case startRequested
        case stopRequested(shiftHeld: Bool)
        case cancelRequested
    }

    public enum Action: Equatable, Sendable {
        case beginRecording
        case finishRecording(autoSend: Bool)
        case cancelRecording
        case ignore
    }

    public private(set) var isRecording = false

    public init() {}

    public mutating func handle(_ event: Event, autoSend mode: AutoSendMode) -> Action {
        switch event {
        case .startRequested:
            guard !isRecording else { return .ignore }
            isRecording = true
            return .beginRecording
        case .stopRequested(let shiftHeld):
            guard isRecording else { return .ignore }
            isRecording = false
            switch mode {
            case .off: return .finishRecording(autoSend: false)
            case .shift: return .finishRecording(autoSend: shiftHeld)
            case .always: return .finishRecording(autoSend: true)
            }
        case .cancelRequested:
            guard isRecording else { return .ignore }
            isRecording = false
            return .cancelRecording
        }
    }
}
