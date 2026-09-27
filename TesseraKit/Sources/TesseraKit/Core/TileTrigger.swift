/// Why a tile is happening, inferred from the change in the window set.
///
/// **Identity matters:** pass stable identities (`MacWindow.stableID`, i.e.
/// `"appName|title"`), never `MacWindow.id`. That is the `AXUIElement` pointer,
/// which is rebuilt on every discovery pass, so the same window changes id
/// between tiles — diffing those would report every window as removed and
/// inserted, making every relayout animate.
///
/// Tessera funnels every layout change — auto-tile on window create/destroy,
/// reload, split toggle, layout-mode switch, display change — through one code
/// path. Rather than making each of those callers declare its own intent (and
/// eventually get it wrong in a new call site), the trigger is *derived* by
/// diffing the window IDs before and after the layout is computed. That makes
/// the classification impossible to forget, and it is pure set arithmetic, so
/// it lives in the Brain layer under test.
public enum TileTrigger: String, Equatable, Sendable {
    /// First tile after the daemon starts. Windows are wherever the user left
    /// them; a staggered cascade here would be noise, so it places instantly.
    case initial
    /// A window appeared. Only the newcomer glides; the windows reflowing to
    /// make room for it snap, so the new tile is easy to track.
    case insert
    /// A window went away. The survivors glide into the space it left, which
    /// is the one reflow users actually watch.
    case remove
    /// Same windows, different targets: layout mode, split toggle, split
    /// resize, display change, or an explicit "Tile Now". Deliberately
    /// instant — this is Tessera's core selling point and the case where an
    /// AX-driven animation is least convincing anyway.
    case relayout
}

/// The trigger plus which windows should animate as a result.
public struct TileTriggerAnalysis: Equatable, Sendable {
    public let trigger: TileTrigger
    /// IDs present now but not before.
    public let inserted: Set<String>
    /// IDs present before but not now.
    public let removed: Set<String>
    /// IDs that should glide. Empty means "place everything instantly".
    public let animated: Set<String>

    public init(trigger: TileTrigger, inserted: Set<String>, removed: Set<String>, animated: Set<String>) {
        self.trigger = trigger
        self.inserted = inserted
        self.removed = removed
        self.animated = animated
    }
}

public enum TileTriggerAnalyzer {
    /// Classify a tile by diffing the window set before and after.
    ///
    /// - Parameters:
    ///   - previous: stable identities known before this tile ran. Empty on the
    ///     first tile after launch.
    ///   - current: stable identities that exist now.
    public static func analyze(previous: Set<String>, current: Set<String>) -> TileTriggerAnalysis {
        let inserted = current.subtracting(previous)
        let removed = previous.subtracting(current)

        // Order matters: a window appearing is a more noticeable event than
        // the reflow it causes, so a simultaneous open+close animates as an
        // insert (the newcomer glides, the survivors snap).
        let trigger: TileTrigger
        if previous.isEmpty && !current.isEmpty {
            trigger = .initial
        } else if !inserted.isEmpty {
            trigger = .insert
        } else if !removed.isEmpty {
            trigger = .remove
        } else {
            trigger = .relayout
        }

        let animated: Set<String>
        switch trigger {
        case .initial:
            animated = []
        case .insert:
            animated = inserted
        case .remove:
            animated = current
        case .relayout:
            animated = []
        }

        return TileTriggerAnalysis(trigger: trigger, inserted: inserted, removed: removed, animated: animated)
    }
}
