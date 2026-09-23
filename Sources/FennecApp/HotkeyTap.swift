import CoreGraphics
import FennecCore

/// Session-level event tap for push-to-talk.
///
/// The tap source runs on the main run loop, so every callback and every
/// mutation of this object's state happens on the main thread. `@unchecked
/// Sendable` records that, because the compiler cannot see it.
final class HotkeyTap: @unchecked Sendable {
    nonisolated(unsafe) var onEvent: (@Sendable (HotkeyStateMachine.Event) -> Void)?

    private let spec: HotkeySpec
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeyIsDown = false

    private static let escapeKeyCode: Int64 = 53

    init(hotkey: Hotkey) {
        spec = HotkeySpec.spec(for: hotkey)
    }

    func start() {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
            tap.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch (spec.kind, type) {
        case (.modifier(let expected, let flag), .flagsChanged) where keyCode == expected:
            let isDown = event.flags.contains(flag)
            if isDown, !hotkeyIsDown {
                hotkeyIsDown = true
                onEvent?(.startRequested)
            } else if !isDown, hotkeyIsDown {
                hotkeyIsDown = false
                onEvent?(.stopRequested(shiftHeld: event.flags.contains(.maskShift)))
            }
        case (.key(let expected), .keyDown) where keyCode == expected:
            guard !hotkeyIsDown else { break }
            hotkeyIsDown = true
            onEvent?(.startRequested)
        case (.key(let expected), .keyUp) where keyCode == expected:
            guard hotkeyIsDown else { break }
            hotkeyIsDown = false
            onEvent?(.stopRequested(shiftHeld: event.flags.contains(.maskShift)))
        case (_, .keyDown) where keyCode == Self.escapeKeyCode:
            onEvent?(.cancelRequested)
        default:
            break
        }
    }
}
