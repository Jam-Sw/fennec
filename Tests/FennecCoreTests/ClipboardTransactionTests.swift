import AppKit
import Foundation
import Testing
@testable import FennecCore

private func testPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("com.fennec.tests.\(UUID().uuidString)"))
}

@Test func restoreBringsBackNonStringContents() {
    let pasteboard = testPasteboard()
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.fennec.tests.blob"))
    item.setString("original", forType: .string)
    pasteboard.writeObjects([item])

    let write = ClipboardTransaction.write("dictated", to: pasteboard)
    #expect(pasteboard.string(forType: .string) == "dictated")

    let restored = ClipboardTransaction.restore(write, to: pasteboard)
    #expect(restored)
    #expect(pasteboard.string(forType: .string) == "original")
    let blob = pasteboard.pasteboardItems?.first?.data(forType: NSPasteboard.PasteboardType("com.fennec.tests.blob"))
    #expect(blob == Data([1, 2, 3]))
}

@Test func restoreIsSkippedWhenSomeoneElseWrote() {
    let pasteboard = testPasteboard()
    pasteboard.clearContents()
    pasteboard.setString("original", forType: .string)

    let write = ClipboardTransaction.write("dictated", to: pasteboard)
    pasteboard.clearContents()
    pasteboard.setString("user copied this", forType: .string)

    let restored = ClipboardTransaction.restore(write, to: pasteboard)
    #expect(!restored)
    #expect(pasteboard.string(forType: .string) == "user copied this")
}

@Test func writeReusesAPriorSnapshotWhenChangeCountIsUnchanged() {
    let pasteboard = testPasteboard()
    pasteboard.clearContents()
    let priorItem = NSPasteboardItem()
    priorItem.setString("prior", forType: .string)
    pasteboard.writeObjects([priorItem])

    // Taken at key-down, before anything else touches the pasteboard.
    let token = ClipboardTransaction.snapshotToken(pasteboard)
    #expect(token.changeCount == pasteboard.changeCount)

    let write = ClipboardTransaction.write("dictated", to: pasteboard, priorSnapshot: token)
    #expect(write.snapshot == token.snapshot)
}

@Test func writeRecapturesWhenThePriorSnapshotIsStale() {
    let pasteboard = testPasteboard()
    pasteboard.clearContents()
    let priorItem = NSPasteboardItem()
    priorItem.setString("prior", forType: .string)
    pasteboard.writeObjects([priorItem])

    let staleToken = ClipboardTransaction.snapshotToken(pasteboard)

    // Something else writes to the pasteboard after the token was taken
    // (e.g. the user copied something else while still speaking). This
    // moves changeCount, so the stale token must not be trusted.
    pasteboard.clearContents()
    let newerItem = NSPasteboardItem()
    newerItem.setString("newer", forType: .string)
    pasteboard.writeObjects([newerItem])
    #expect(pasteboard.changeCount != staleToken.changeCount)

    let write = ClipboardTransaction.write("dictated", to: pasteboard, priorSnapshot: staleToken)
    #expect(write.snapshot != staleToken.snapshot)

    let restored = ClipboardTransaction.restore(write, to: pasteboard)
    #expect(restored)
    #expect(pasteboard.string(forType: .string) == "newer")
}

@Test func restoreClearsWhenThereWasNothingBefore() {
    let pasteboard = testPasteboard()
    pasteboard.clearContents()

    let write = ClipboardTransaction.write("dictated", to: pasteboard)
    let restored = ClipboardTransaction.restore(write, to: pasteboard)
    #expect(restored)
    #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
}
