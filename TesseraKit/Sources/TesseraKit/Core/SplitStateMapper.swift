import Foundation

/// Translates `SplitState` keys between the two identities a window has.
///
/// `Workspace` keys splits on the window id it was handed, which in the daemon
/// is the `AXUIElement` pointer. That pointer is rebuilt on every discovery
/// pass, so a state captured before a re-tile names windows the rebuilt tree
/// does not contain, and the ratio is silently dropped back to 50/50.
///
/// The daemon maps ids to and from `MacWindow.stableID` around that boundary.
/// This lives in TesseraKit — rather than in the daemon's `WindowMapper` — so it
/// is reachable from the test target, which cannot import the daemon executable.
public enum SplitStateMapper {
    /// Re-key every state, translating each half of its key through
    /// `translation`.
    ///
    /// Halves that `translation` cannot resolve are dropped rather than kept
    /// under their old key: the node then falls back to its default ratio
    /// instead of a ratio captured for a different pair of windows being applied
    /// to whatever node happens to reuse that key.
    ///
    /// A colliding `translation` (two windows mapping to one key) overwrites, so
    /// the last window scanned wins. `MacWindow.stableID` is `"appName|title"`,
    /// so same-titled windows in one app do collide — the same limitation
    /// `floaterKey` carries.
    public static func rekey(_ states: [String: SplitState],
                             using translation: (String) -> String?) -> [String: SplitState] {
        var out: [String: SplitState] = [:]
        for (key, state) in states {
            guard let parts = SplitStateKey.parse(key),
                  let left = translation(parts.left),
                  let right = translation(parts.right) else { continue }
            out[SplitStateKey.make(left: left, right: right)] = state
        }
        return out
    }

    /// Convenience for the common case of two parallel id lists. Mismatched
    /// counts yield an empty result rather than a partial, misaligned mapping.
    public static func rekey(_ states: [String: SplitState],
                             from oldIDs: [String],
                             to newIDs: [String]) -> [String: SplitState] {
        guard oldIDs.count == newIDs.count else { return [:] }
        let lookup = Dictionary(zip(oldIDs, newIDs), uniquingKeysWith: { first, _ in first })
        return rekey(states, using: { lookup[$0] })
    }
}
