import CoreGraphics
import Foundation
import Testing
@testable import FennecCore

actor KeyLog {
    private(set) var keys: [CGKeyCode] = []
    func append(_ key: CGKeyCode) { keys.append(key) }
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
