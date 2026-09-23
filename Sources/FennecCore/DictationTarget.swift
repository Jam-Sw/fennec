import Foundation

/// The app a dictation started in, captured before any awaits so a later
/// dictation cannot overwrite it.
public struct DictationTarget: Equatable, Sendable {
    public let pid: pid_t

    public init(pid: pid_t) {
        self.pid = pid
    }

    public static func capture(frontmostPID: pid_t?) -> DictationTarget {
        DictationTarget(pid: frontmostPID ?? 0)
    }

    public func stillFocused(currentPID: pid_t?) -> Bool {
        (currentPID ?? 0) == pid
    }
}
