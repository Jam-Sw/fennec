import CoreGraphics

/// Which physical key a configured hotkey means, and whether it arrives as a
/// modifier flag change or as a plain key press.
public struct HotkeySpec: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case modifier(keyCode: Int64, flag: CGEventFlags)
        case key(keyCode: Int64)
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public static func spec(for hotkey: Hotkey) -> HotkeySpec {
        switch hotkey {
        case .rightOption:
            return HotkeySpec(kind: .modifier(keyCode: 61, flag: .maskAlternate))
        case .rightCommand:
            return HotkeySpec(kind: .modifier(keyCode: 54, flag: .maskCommand))
        case .fn:
            return HotkeySpec(kind: .modifier(keyCode: 63, flag: .maskSecondaryFn))
        case .f13:
            return HotkeySpec(kind: .key(keyCode: 105))
        }
    }
}
