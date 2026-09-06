/// Reorders windows so they keep their tile slots across re-tiles.
///
/// The BSP greedy partition produces an order-invariant set of leaf geometries,
/// so which window lands in which leaf is purely a matter of assignment
/// (insertion order). By feeding the previous layout's window order back into
/// the rebuild we keep every existing window in the same leaf — its "slot" —
/// while brand-new windows take the remaining slots at the tail.
public enum WindowOrdering {
    /// Returns `current` with items whose key appears in `previousKeyOrder`
    /// kept in that relative order; brand-new items sort to the tail using
    /// `sortNew`. Each current item is matched at most once.
    public static func reorder<T>(
        _ current: [T],
        previousKeyOrder: [String],
        matchingKey: (T) -> String,
        sortNew: (T, T) -> Bool
    ) -> [T] {
        guard !previousKeyOrder.isEmpty else {
            return current.sorted(by: sortNew)
        }

        var remaining = current
        var ordered: [T] = []
        ordered.reserveCapacity(current.count)

        for key in previousKeyOrder {
            guard let index = remaining.firstIndex(where: { matchingKey($0) == key }) else { continue }
            ordered.append(remaining.remove(at: index))
        }

        if remaining.count > 1 {
            remaining.sort(by: sortNew)
        }
        ordered.append(contentsOf: remaining)
        return ordered
    }
}