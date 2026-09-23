import CoreGraphics
import Foundation
import Testing
@testable import FennecCore

@Test func hotkeySpecsMapToTheRightKeys() {
    #expect(HotkeySpec.spec(for: .rightOption) == HotkeySpec(kind: .modifier(keyCode: 61, flag: .maskAlternate)))
    #expect(HotkeySpec.spec(for: .rightCommand) == HotkeySpec(kind: .modifier(keyCode: 54, flag: .maskCommand)))
    #expect(HotkeySpec.spec(for: .fn) == HotkeySpec(kind: .modifier(keyCode: 63, flag: .maskSecondaryFn)))
    #expect(HotkeySpec.spec(for: .f13) == HotkeySpec(kind: .key(keyCode: 105)))
}
