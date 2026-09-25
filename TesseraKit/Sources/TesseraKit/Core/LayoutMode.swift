/// The tiling algorithm applied to every display's window stack.
///
/// A "preset" fixes the way windows are arranged (not their sizes/positions,
/// which are still derived live from the screen). Tiling always rebuilds each
/// display's tree from its ordered window stack, so a mode is just the recipe
/// used to build that tree from the same ordered list.
public enum LayoutMode: String, Codable, CaseIterable, Sendable, Equatable {
    /// Binary space partition — the classic Tessera tree (left/right or top/
    /// bottom splits of the largest leaf). This is the default and the only
    /// mode that supports split-direction toggling per node.
    case bsp
    /// One master pane at a fixed ratio, remaining windows stacked as rows
    /// in the leftover column (Amethyst-style "Tall").
    case masterStack = "masterStack"
    /// All windows side-by-side as equal-width columns (Amethyst "Columns").
    case columns

    /// Next mode in cycling order: bsp → masterStack → columns → bsp.
    public func next() -> LayoutMode {
        let all = LayoutMode.allCases
        guard let idx = all.firstIndex(of: self) else { return .bsp }
        return all[(idx + 1) % all.count]
    }
}