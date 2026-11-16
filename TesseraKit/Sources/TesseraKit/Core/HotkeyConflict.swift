import Foundation

/// What claiming a combo would cost: the other actions it displaces and/or
/// the macOS system shortcut it collides with.
public struct HotkeyConflict: Equatable, Sendable {
    /// Actions (other than the one being bound) that lose a binding because
    /// `HotkeyBindings.merge` frees the claimed key code. Sorted, unique.
    public var displacedActions: [String]
    /// Display form (e.g. `"⌘Space"`) of a known macOS system shortcut that
    /// the combo matches exactly, if any.
    public var systemShortcut: String?

    public init(displacedActions: [String] = [], systemShortcut: String? = nil) {
        self.displacedActions = displacedActions
        self.systemShortcut = systemShortcut
    }

    public var isEmpty: Bool { displacedActions.isEmpty && systemShortcut == nil }
}

public enum HotkeyConflicts {
    /// Well-known macOS shortcuts that a user is likely to collide with.
    /// Matched on exact key code and exact modifier set.
    public static let systemShortcuts: [HotkeyBinding] = [
        HotkeyBinding(action: "", keyCode: 49, flags: ["cmd"]),          // Space (Spotlight)
        HotkeyBinding(action: "", keyCode: 48, flags: ["cmd"]),          // Tab (app switcher)
        HotkeyBinding(action: "", keyCode: 12, flags: ["cmd"]),          // Q
        HotkeyBinding(action: "", keyCode: 13, flags: ["cmd"]),          // W
        HotkeyBinding(action: "", keyCode: 4, flags: ["cmd"]),           // H
        HotkeyBinding(action: "", keyCode: 46, flags: ["cmd"]),          // M
        HotkeyBinding(action: "", keyCode: 43, flags: ["cmd"]),          // Comma (Preferences)
        HotkeyBinding(action: "", keyCode: 20, flags: ["cmd", "shift"]), // 3 (screenshot)
        HotkeyBinding(action: "", keyCode: 21, flags: ["cmd", "shift"]), // 4 (screenshot area)
        HotkeyBinding(action: "", keyCode: 23, flags: ["cmd", "shift"]), // 5 (screenshot menu)
    ]

    /// Checks a proposed binding of `action` to `keyCode` + `flags` against
    /// `bindings` (the currently resolved set, e.g. `HotkeyBindings.merge` output).
    ///
    /// Displacement follows `HotkeyBindings.merge`, which frees the claimed key
    /// code regardless of modifiers, so a different modifier set on the same key
    /// still displaces the other action. Pure: does not modify `bindings`.
    public static func check(action: String,
                             keyCode: UInt16,
                             flags: [String],
                             against bindings: [HotkeyBinding]) -> HotkeyConflict {
        let displaced = Set(bindings
            .filter { $0.keyCode == keyCode && $0.action != action }
            .map(\.action))
            .sorted()

        let normalized = Set(HotkeyBindings.normalizedFlags(flags))
        let system = systemShortcuts.first {
            $0.keyCode == keyCode && Set($0.flags) == normalized
        }?.display

        return HotkeyConflict(displacedActions: displaced, systemShortcut: system)
    }
}
