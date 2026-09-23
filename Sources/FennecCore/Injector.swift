import AppKit
import Carbon
import CoreGraphics
import Foundation

public actor Injector {
    public typealias KeyPoster = @Sendable (CGKeyCode, CGEventFlags) -> Void

    nonisolated(unsafe) private let pasteboard: NSPasteboard
    private let postKey: KeyPoster

    public init(
        pasteboardName: String? = nil,
        postKey: @escaping KeyPoster = Injector.postToSystem
    ) {
        if let pasteboardName {
            self.pasteboard = NSPasteboard(name: NSPasteboard.Name(pasteboardName))
        } else {
            self.pasteboard = NSPasteboard.general
        }
        self.postKey = postKey
    }

    /// Write the text, let the focused app settle, then post Cmd+V.
    ///
    /// `verifyTarget` runs again immediately before the keystrokes, so a focus
    /// change in the settle window never pastes into the wrong app. When it
    /// fails, nothing is posted and the transcript is left on the clipboard.
    @discardableResult
    public func paste(
        _ text: String,
        autoSend: Bool,
        verifyTarget: (@Sendable () async -> Bool)? = nil
    ) async -> Bool {
        let write = ClipboardTransaction.write(text, to: pasteboard)
        try? await Task.sleep(nanoseconds: 100_000_000)
        if let verifyTarget, await verifyTarget() == false {
            return false
        }
        postKey(await MainActor.run { Self.pasteKeyCode() }, .maskCommand)
        if autoSend {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let verifyTarget, await verifyTarget() == false {
                return false
            }
            postKey(36, [])
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        ClipboardTransaction.restore(write, to: pasteboard)
        return true
    }

    /// The key that gives "v" with Command held in the current keyboard layout,
    /// so the paste shortcut is right on Dvorak, AZERTY, and similar layouts.
    /// Falls back to the ANSI V position.
    @MainActor
    public static func pasteKeyCode() -> CGKeyCode {
        let ansiV: CGKeyCode = 9
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return ansiV
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return ansiV
            }
            let commandState = UInt32((cmdKey >> 8) & 0xFF)
            for code in UInt16(0) ..< 128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), commandState, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
                )
                if status == noErr, length == 1, characters[0] == UniChar(118) {
                    return CGKeyCode(code)
                }
            }
            return ansiV
        }
    }

    public static func postToSystem(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
