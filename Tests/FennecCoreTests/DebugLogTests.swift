import Foundation
import Testing
@testable import FennecCore

@Test func debugLogWritesWhenEnabled() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("fennec.log")
    DebugLog(enabled: true, url: url).record("hello")
    let contents = try String(contentsOf: url, encoding: .utf8)
    #expect(contents.contains("hello"))
}

@Test func debugLogIsSilentWhenDisabled() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    DebugLog(enabled: false, url: url).record("hello")
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
