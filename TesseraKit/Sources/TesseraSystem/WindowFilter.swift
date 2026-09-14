import CoreGraphics
import Foundation
import TesseraKit

/// Pure window classification used to decide which windows the tiler tiles.
/// Operates on primitive values so it can be unit-tested without AX elements.
public enum WindowFilter {

    /// Only `AXWindow` elements are tileable.
    public static func isStandardRole(_ role: String?) -> Bool {
        role == "AXWindow"
    }

    /// True when `subrole` is in the configured exclusion set.
    public static func isExcludedSubrole(_ subrole: String?, excluded: Set<String>) -> Bool {
        guard let subrole else { return false }
        return excluded.contains(subrole)
    }

    /// Combined tileability check: standard role, non-excluded subrole, and a
    /// non-zero size (hidden/off-stage windows report zero dimensions).
    public static func isTileable(
        role: String?,
        subrole: String?,
        size: CGSize,
        excludedSubroles: Set<String>
    ) -> Bool {
        guard isStandardRole(role) else { return false }
        guard !isExcludedSubrole(subrole, excluded: excludedSubroles) else { return false }
        return size.width > 0 && size.height > 0
    }
}