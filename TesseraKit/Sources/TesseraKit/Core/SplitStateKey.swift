import Foundation

/// Identity for a split node, used to re-attach a saved `SplitState` to the
/// right node after the tree has been rebuilt.
///
/// A node is identified by the two outermost leaf windows beneath it, because
/// a single window id is not unique — nested splits on the same path share a
/// leftmost leaf. The pair is stable while both windows exist.
///
/// ## Why the separator is not `|`
///
/// The daemon remaps these ids to `MacWindow.stableID` (`"appName|title"`) so
/// they survive a discovery pass, and an app name or window title can contain
/// `|` freely. Joining the two halves with `|` would make `"a|b|c"` ambiguous
/// and impossible to parse back. `U+001E` is a record separator: not something
/// a user types into a window title.
public enum SplitStateKey {
    static let separator = "\u{001E}"

    public static func make(left: String, right: String) -> String {
        return left + separator + right
    }

    /// The two halves, or nil if `key` was not produced by `make`. Legacy
    /// `|`-joined keys fail here, which is deliberate: they name windows that
    /// no longer exist, and dropping them degrades to the 50/50 default rather
    /// than applying a ratio to the wrong node.
    public static func parse(_ key: String) -> (left: String, right: String)? {
        let parts = key.components(separatedBy: separator)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}
