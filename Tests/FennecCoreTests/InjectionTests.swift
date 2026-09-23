import Foundation
import Testing
@testable import FennecCore

@Test func policyPastesWhenEverythingIsFine() {
    let outcome = InjectionPolicy.decide(hasText: true, focusChanged: false, secureInput: false, canPostKeys: true, autoSend: true)
    #expect(outcome == .paste(autoSend: true))
}

@Test func policyWithholdsOnEmptyText() {
    let outcome = InjectionPolicy.decide(hasText: false, focusChanged: false, secureInput: false, canPostKeys: true, autoSend: false)
    #expect(outcome == .clipboardOnly(reason: .noSpeech))
}

@Test func policyWithholdsOnSecureInput() {
    let outcome = InjectionPolicy.decide(hasText: true, focusChanged: false, secureInput: true, canPostKeys: true, autoSend: false)
    #expect(outcome == .clipboardOnly(reason: .secureInput))
}

@Test func policyWithholdsOnFocusChange() {
    let outcome = InjectionPolicy.decide(hasText: true, focusChanged: true, secureInput: false, canPostKeys: true, autoSend: false)
    #expect(outcome == .clipboardOnly(reason: .focusChanged))
}

@Test func policyWithholdsWhenKeystrokesWouldBeDropped() {
    let outcome = InjectionPolicy.decide(hasText: true, focusChanged: false, secureInput: false, canPostKeys: false, autoSend: true)
    #expect(outcome == .clipboardOnly(reason: .notTrusted))
}

@Test func policyReportsNoSpeechBeforeTrust() {
    let outcome = InjectionPolicy.decide(hasText: false, focusChanged: false, secureInput: false, canPostKeys: false, autoSend: false)
    #expect(outcome == .clipboardOnly(reason: .noSpeech))
}

@Test func clipboardGuardRestoresOnlyWhenUnchanged() {
    #expect(ClipboardGuard.shouldRestore(
        ourChangeCount: 10, ourString: "fennec",
        currentChangeCount: 10, currentString: "fennec"
    ))
    #expect(!ClipboardGuard.shouldRestore(
        ourChangeCount: 10, ourString: "fennec",
        currentChangeCount: 11, currentString: "fennec"
    ))
    #expect(!ClipboardGuard.shouldRestore(
        ourChangeCount: 10, ourString: "fennec",
        currentChangeCount: 10, currentString: "something else"
    ))
    #expect(!ClipboardGuard.shouldRestore(
        ourChangeCount: 10, ourString: "fennec",
        currentChangeCount: 10, currentString: nil
    ))
}
