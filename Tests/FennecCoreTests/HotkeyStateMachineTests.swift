import Foundation
import Testing
@testable import FennecCore

@Test func startThenStopOrdersEvents() {
    var machine = HotkeyStateMachine()
    #expect(machine.handle(.startRequested, autoSend: .off) == .beginRecording)
    #expect(machine.isRecording)
    #expect(machine.handle(.startRequested, autoSend: .off) == .ignore)
    #expect(machine.handle(.stopRequested(shiftHeld: false), autoSend: .off) == .finishRecording(autoSend: false))
    #expect(!machine.isRecording)
}

@Test func shiftModeArmsAutoSendOnRelease() {
    var machine = HotkeyStateMachine()
    _ = machine.handle(.startRequested, autoSend: .shift)
    #expect(machine.handle(.stopRequested(shiftHeld: true), autoSend: .shift) == .finishRecording(autoSend: true))

    _ = machine.handle(.startRequested, autoSend: .shift)
    #expect(machine.handle(.stopRequested(shiftHeld: false), autoSend: .shift) == .finishRecording(autoSend: false))
}

@Test func alwaysModeIgnoresShift() {
    var machine = HotkeyStateMachine()
    _ = machine.handle(.startRequested, autoSend: .always)
    #expect(machine.handle(.stopRequested(shiftHeld: false), autoSend: .always) == .finishRecording(autoSend: true))
}

@Test func cancelOnlyAppliesWhileRecording() {
    var machine = HotkeyStateMachine()
    #expect(machine.handle(.cancelRequested, autoSend: .off) == .ignore)
    _ = machine.handle(.startRequested, autoSend: .off)
    #expect(machine.handle(.cancelRequested, autoSend: .off) == .cancelRecording)
    #expect(!machine.isRecording)
}
