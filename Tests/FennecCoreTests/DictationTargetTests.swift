import Foundation
import Testing
@testable import FennecCore

@Test func targetKeepsThePidItCaptured() {
    let target = DictationTarget.capture(frontmostPID: 42)
    #expect(target.stillFocused(currentPID: 42))
    #expect(!target.stillFocused(currentPID: 43))
    #expect(!target.stillFocused(currentPID: nil))
}

@Test func targetWithNoPidMatchesOnlyAnotherUnknown() {
    let target = DictationTarget.capture(frontmostPID: nil)
    #expect(target.stillFocused(currentPID: nil))
    #expect(!target.stillFocused(currentPID: 42))
}
