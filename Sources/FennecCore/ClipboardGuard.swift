import Foundation

public enum ClipboardGuard {
    /// Restore the previous clipboard only when nothing has touched it since
    /// our write. Anything else means the user, or another app, has moved on.
    public static func shouldRestore(
        ourChangeCount: Int,
        ourString: String,
        currentChangeCount: Int,
        currentString: String?
    ) -> Bool {
        currentChangeCount == ourChangeCount && currentString == ourString
    }
}
