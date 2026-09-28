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

    /// Captures the current pasteboard contents. Call this at key-down, while
    /// the user is still speaking, so the (potentially large) capture is off
    /// the paste critical path; hand the result to `paste(priorSnapshot:)`.
    public func snapshotToken() -> ClipboardSnapshotToken {
        ClipboardTransaction.snapshotToken(pasteboard)
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
        verifyTarget: (@Sendable () async -> Bool)? = nil,
        priorSnapshot: ClipboardSnapshotToken? = nil,
        settleSeconds: Double = 0.02,
        since start: CFAbsoluteTime? = nil,
        onStage: (@Sendable (String, Int) -> Void)? = nil
    ) async -> Bool {
        func mark(_ stage: String) {
            guard let start, let onStage else { return }
            onStage(stage, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
        }
        let write = ClipboardTransaction.write(text, to: pasteboard, priorSnapshot: priorSnapshot)
        mark("snapshot")
        try? await Task.sleep(nanoseconds: UInt64(max(0, settleSeconds) * 1_000_000_000))
        mark("settle")
        if let verifyTarget, await verifyTarget() == false {
            return false
        }
        postKey(await MainActor.run { Self.cachedPasteKeyCode() }, .maskCommand)
        mark("post")
        if autoSend {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let verifyTarget, await verifyTarget() == false {
                ClipboardTransaction.restore(write, to: pasteboard)
                return false
            }
            postKey(36, [])
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        ClipboardTransaction.restore(write, to: pasteboard)
        return true
    }

    /// Types text as keystrokes carrying Unicode strings, leaving the
    /// clipboard alone. Live typing sends many small pieces, and a clipboard
    /// round-trip for each would be slow and would race the user's own copies.
    /// The modifier flags are cleared so the held hotkey does not turn the
    /// letters into Option-characters.
    public static func typeToSystem(_ text: String) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let units = Array(text.utf16)
        // Events carry at most 20 UTF-16 units; longer strings are truncated.
        var index = 0
        while index < units.count {
            var end = min(index + 20, units.count)
            // Keep a surrogate pair together.
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            var chunk = Array(units[index ..< end])
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.flags = []
            up?.flags = []
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            up?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            index = end
        }
    }

    /// Posts Return, for auto-send after live typing.
    public func pressReturn() {
        postKey(36, [])
    }

    /// Caches `pasteKeyCode()` so a paste doesn't pay for a 128-code
    /// `UCKeyTranslate` scan every time; invalidated when the keyboard input
    /// source changes.
    @MainActor
    private final class PasteKeyCodeCache {
        static let shared = PasteKeyCodeCache()
        private var cached: CGKeyCode?
        private var observer: NSObjectProtocol?

        private init() {
            observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in self?.cached = nil }
            }
        }

        func keyCode() -> CGKeyCode {
            if let cached { return cached }
            let value = Injector.pasteKeyCode()
            cached = value
            return value
        }
    }

    @MainActor
    public static func cachedPasteKeyCode() -> CGKeyCode {
        PasteKeyCodeCache.shared.keyCode()
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
