/// Per-display tiling configuration.
public struct MultiMonitorConfig: Sendable, Equatable {
    /// How focus navigation behaves across displays:
    /// - `"withinDisplay"`: H/J/K/L/I/M operate only on the display holding the focused window (default)
    /// - `"crossDisplay"`: reserved for future edge-crossing focus
    public var focusMode: String

    public init(focusMode: String = "withinDisplay") {
        self.focusMode = focusMode
    }
}

public struct TesseraConfig: Sendable {
    public var gapSize: Double
    public var outerGap: Double
    public var initialSplit: SplitType
    public var newWindowFocus: Bool
    public var floatingAppIDs: [String]
    public var animationEnabled: Bool
    public var animationSteps: Int
    public var animationDuration: Double
    public var multiMonitor: MultiMonitorConfig

    public init(
        gapSize: Double = 8,
        outerGap: Double = 4,
        initialSplit: SplitType = .vertical,
        newWindowFocus: Bool = false,
        floatingAppIDs: [String] = [],
        animationEnabled: Bool = true,
        animationSteps: Int = 8,
        animationDuration: Double = 0.15,
        multiMonitor: MultiMonitorConfig = MultiMonitorConfig()
    ) {
        self.gapSize = gapSize
        self.outerGap = outerGap
        self.initialSplit = initialSplit
        self.newWindowFocus = newWindowFocus
        self.floatingAppIDs = floatingAppIDs
        self.animationEnabled = animationEnabled
        self.animationSteps = animationSteps
        self.animationDuration = animationDuration
        self.multiMonitor = multiMonitor
    }
}
