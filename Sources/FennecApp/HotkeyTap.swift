import CoreGraphics
import FennecCore

/// Session-level event tap for push-to-talk.
///
/// The tap source runs on the main run loop, so every callback and every
/// mutation of this object's state happens on the main thread. `@unchecked
/// Sendable` records that, because the compiler cannot see it.
final class HotkeyTap: @unchecked Sendable {
    nonisolated(unsafe) var onEvent: (@Sendable (HotkeyStateMachine.Event) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var optionIsDown = false

    private static let rightOptionKeyCode: Int64 = 61
    private static let escapeKeyCode: Int64 = 53

    func start() {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
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
        switch type {
        case .flagsChanged where keyCode == Self.rightOptionKeyCode:
            let isDown = event.flags.contains(.maskAlternate)
            if isDown, !optionIsDown {
                optionIsDown = true
                onEvent?(.startRequested)
            } else if !isDown, optionIsDown {
                optionIsDown = false
                onEvent?(.stopRequested(shiftHeld: event.flags.contains(.maskShift)))
            }
        case .keyDown where keyCode == Self.escapeKeyCode:
            onEvent?(.cancelRequested)
        default:
            break
        }
    }
}
