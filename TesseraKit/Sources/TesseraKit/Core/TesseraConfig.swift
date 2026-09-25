/// Per-display tiling configuration.
public struct MultiMonitorConfig: Sendable, Equatable {
    /// How focus navigation behaves across displays:
    /// - `"withinDisplay"`: H/J/K/L/I/M operate only on the display holding the focused window (default)
    /// - `"crossDisplay"`: reserved for future edge-crossing focus
    public var focusMode: String

    public init(focusMode: String = "withinDisplay") {
        self.focusMode = focusMode
    }

    public static func == (lhs: MultiMonitorConfig, rhs: MultiMonitorConfig) -> Bool {
        lhs.focusMode == rhs.focusMode
    }

    public static func != (lhs: MultiMonitorConfig, rhs: MultiMonitorConfig) -> Bool {
        return !(lhs == rhs)
    }
}

/// Tiling configuration passed to the Workspace and Tiler.
public struct TesseraConfig: Sendable, Equatable {
    public var gapSize: Double
    public var outerGap: Double
    public var initialSplit: SplitType
    /// The tiling algorithm applied at startup (see `LayoutMode`). The daemon
    /// can cycle through modes at runtime without touching this file.
    public var layoutMode: LayoutMode
    /// Fraction of the screen given to the master pane in `masterStack` mode
    /// (0 < masterRatio < 1).
    public var masterRatio: Double
    /// How much one ⌘⌥[ / ⌘⌥] press moves the focused bsp split's ratio.
    public var splitResizeStep: Double
    /// Floor/ceiling clamping split ratios to (0…1). Keeps any pane from
    /// collapsing to zero.
    public var splitMinRatio: Double
    public var splitMaxRatio: Double
    public var newWindowFocus: Bool
    public var floatingAppIDs: [String]
    /// Per-app tiling rules: app bundle ID → how it's tiled.
    public var appRules: [String: AppTilingRule]
    /// Window subroles that are never tiled. Defaults to `AXSubrole.excludedDefaults`; a
    /// config-provided value replaces the built-in set entirely.
    public var excludedSubroles: [String]
    public var animationEnabled: Bool
    public var animationSteps: Int
    public var animationDuration: Double
    public var multiMonitor: MultiMonitorConfig

    public init(
        gapSize: Double = 8,
        outerGap: Double = 4,
        initialSplit: SplitType = .vertical,
        layoutMode: LayoutMode = .bsp,
        masterRatio: Double = 0.6,
        splitResizeStep: Double = 0.10,
        splitMinRatio: Double = 0.2,
        splitMaxRatio: Double = 0.8,
        newWindowFocus: Bool = false,
        floatingAppIDs: [String] = [],
        appRules: [String: AppTilingRule] = [:],
        excludedSubroles: [String] = Array(AXSubrole.excludedDefaults).sorted(),
        animationEnabled: Bool = true,
        animationSteps: Int = 8,
        animationDuration: Double = 0.15,
        multiMonitor: MultiMonitorConfig = MultiMonitorConfig()
    ) {
        self.gapSize = gapSize
        self.outerGap = outerGap
        self.initialSplit = initialSplit
        self.layoutMode = layoutMode
        self.masterRatio = masterRatio
        self.splitResizeStep = splitResizeStep
        self.splitMinRatio = splitMinRatio
        self.splitMaxRatio = splitMaxRatio
        self.newWindowFocus = newWindowFocus
        self.floatingAppIDs = floatingAppIDs
        self.appRules = appRules
        self.excludedSubroles = excludedSubroles
        self.animationEnabled = animationEnabled
        self.animationSteps = animationSteps
        self.animationDuration = animationDuration
        self.multiMonitor = multiMonitor
    }

    public static func == (lhs: TesseraConfig, rhs: TesseraConfig) -> Bool {
        lhs.gapSize == rhs.gapSize &&
            lhs.outerGap == rhs.outerGap &&
            lhs.initialSplit == rhs.initialSplit &&
            lhs.layoutMode == rhs.layoutMode &&
            lhs.masterRatio == rhs.masterRatio &&
            lhs.splitResizeStep == rhs.splitResizeStep &&
            lhs.splitMinRatio == rhs.splitMinRatio &&
            lhs.splitMaxRatio == rhs.splitMaxRatio &&
            lhs.newWindowFocus == rhs.newWindowFocus &&
            lhs.floatingAppIDs == rhs.floatingAppIDs &&
            lhs.appRules == rhs.appRules &&
            lhs.excludedSubroles == rhs.excludedSubroles &&
            lhs.animationEnabled == rhs.animationEnabled &&
            lhs.animationSteps == rhs.animationSteps &&
            lhs.animationDuration == rhs.animationDuration &&
            lhs.multiMonitor == rhs.multiMonitor
    }

    public static func != (lhs: TesseraConfig, rhs: TesseraConfig) -> Bool {
        return !(lhs == rhs)
    }
}
