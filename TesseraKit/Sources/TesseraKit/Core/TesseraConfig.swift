public struct TesseraConfig: Sendable {
    public var gapSize: Double
    public var outerGap: Double
    public var initialSplit: SplitType
    public var newWindowFocus: Bool

    public init(
        gapSize: Double = 8,
        outerGap: Double = 4,
        initialSplit: SplitType = .vertical,
        newWindowFocus: Bool = false
    ) {
        self.gapSize = gapSize
        self.outerGap = outerGap
        self.initialSplit = initialSplit
        self.newWindowFocus = newWindowFocus
    }
}
