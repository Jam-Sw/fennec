import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import FennecCore

actor KeyLog {
    private(set) var keys: [CGKeyCode] = []
    func append(_ key: CGKeyCode) { keys.append(key) }
}

/// Records keys synchronously so a test can assert on them immediately after
/// `paste` returns, without the fire-and-forget sleep used by the legacy tests.
final class LockedKeyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CGKeyCode] = []

    func append(_ key: CGKeyCode) {
        lock.lock()
        values.append(key)
        lock.unlock()
    }

    var keys: [CGKeyCode] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

/// Returns a fixed sequence of `verifyTarget` results, one per call.
final class VerifySequence: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Bool]
    private var count = 0

    init(_ responses: [Bool]) {
        self.responses = responses
    }

    func next() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return responses.isEmpty ? false : responses.removeFirst()
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@Test func pastePostsCommandVAndRestores() async {
    let log = KeyLog()
    let injector = Injector(pasteboardName: "com.fennec.tests.\(UUID().uuidString)") { keyCode, _ in
        Task { await log.append(keyCode) }
    }
    let posted = await injector.paste("hello", autoSend: false, verifyTarget: { true })
    #expect(posted)
    try? await Task.sleep(nanoseconds: 500_000_000)
    #expect(await log.keys == [9])
}

@Test func pasteSkipsKeysWhenTheTargetCheckFails() async {
    let log = KeyLog()
    let injector = Injector(pasteboardName: "com.fennec.tests.\(UUID().uuidString)") { keyCode, _ in
        Task { await log.append(keyCode) }
    }
    let posted = await injector.paste("hello", autoSend: false, verifyTarget: { false })
    #expect(!posted)
    try? await Task.sleep(nanoseconds: 500_000_000)
    #expect(await log.keys.isEmpty)
}

@Test func autoSendPostsReturnAfterCommandV() async {
    let log = KeyLog()
    let injector = Injector(pasteboardName: "com.fennec.tests.\(UUID().uuidString)") { keyCode, _ in
        Task { await log.append(keyCode) }
    }
    let posted = await injector.paste("hello", autoSend: true, verifyTarget: { true })
    #expect(posted)
    try? await Task.sleep(nanoseconds: 700_000_000)
    #expect(await log.keys == [9, 36])
}

@Test func snapshotTokenRoundTripsThroughInjector() async {
    let pasteboardName = "com.fennec.tests.\(UUID().uuidString)"
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(pasteboardName))
    pasteboard.clearContents()
    let priorItem = NSPasteboardItem()
    priorItem.setString("prior", forType: .string)
    pasteboard.writeObjects([priorItem])

    let injector = Injector(pasteboardName: pasteboardName) { _, _ in }
    let token = await injector.snapshotToken()
    #expect(token.changeCount == pasteboard.changeCount)

    let posted = await injector.paste("hello", autoSend: false, verifyTarget: { true }, priorSnapshot: token)
    #expect(posted)
    try? await Task.sleep(nanoseconds: 300_000_000)
    #expect(pasteboard.string(forType: .string) == "prior")
}

@Test func autoSendRestoresClipboardAndWithholdsReturnWhenSecondVerifyFails() async {
    let pasteboardName = "com.fennec.tests.\(UUID().uuidString)"
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(pasteboardName))
    pasteboard.clearContents()
    let priorItem = NSPasteboardItem()
    priorItem.setString("prior", forType: .string)
    pasteboard.writeObjects([priorItem])

    let keys = LockedKeyLog()
    let verify = VerifySequence([true, false])
    let injector = Injector(pasteboardName: pasteboardName) { keyCode, _ in
        keys.append(keyCode)
    }

    let posted = await injector.paste("hello", autoSend: true) {
        verify.next()
    }

    #expect(!posted)
    #expect(verify.callCount == 2)
    #expect(keys.keys == [9])
    #expect(pasteboard.string(forType: .string) == "prior")
}
