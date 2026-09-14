/// Well-known macOS accessibility subrole/role identifiers used by the tiler.
public enum AXSubrole {
    /// Built-in set of window subroles that are never tiled (dialogs, sheets,
    /// floating/status/help panels, popovers). Config-provided
    /// `excludedSubroles` replaces this set entirely when present.
    public static let excludedDefaults: Set<String> = [
        "AXDialog",
        "AXSystemDialog",
        "AXSheet",
        "AXSystemSheet",
        "AXFloatingWindow",
        "AXSystemFloatingWindow",
        "AXStatusWindow",
        "AXSystemStatusWindow",
        "AXHelpWindow",
        "AXPopover",
    ]
}