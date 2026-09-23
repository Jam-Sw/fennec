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

@Test func restoreClearsWhenThereWasNothingBefore() {
    let pasteboard = testPasteboard()
    pasteboard.clearContents()

    let write = ClipboardTransaction.write("dictated", to: pasteboard)
    let restored = ClipboardTransaction.restore(write, to: pasteboard)
    #expect(restored)
    #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
}
