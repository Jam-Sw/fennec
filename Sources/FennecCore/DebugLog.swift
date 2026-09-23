import Foundation

public struct DebugLog: Sendable {
    public var enabled: Bool
    public var url: URL

    public init(
        enabled: Bool,
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Fennec/fennec.log")
    ) {
        self.enabled = enabled
        self.url = url
    }

    public func record(_ message: String) {
        guard enabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url)
        }
    }
}
