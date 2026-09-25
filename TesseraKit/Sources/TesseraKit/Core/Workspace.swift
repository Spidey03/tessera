/// A split's persisted state: how much of the parent rect the FIRST child gets
/// (`ratio`) and which way the split points (`orientation`).
public struct SplitState: Codable, Sendable, Equatable {
    public var ratio: Double
    public var orientation: SplitType

    public init(ratio: Double, orientation: SplitType) {
        self.ratio = ratio
        self.orientation = orientation
    }
}

public final class Workspace: @unchecked Sendable {
    public let monitorRect: Rect
    public let config: TesseraConfig
    public private(set) var root: TreeNode?
    public private(set) var nextSplit: SplitType
    /// Layout mode last applied via `applyPreset` (nil until tiled). Drives
    /// whether split ratios are meaningful: only the bsp tree recomputes
    /// geometry from `node.ratio` (reflow), masterStack/columns store geometry
    /// on leaves and ignore ratios.
    public private(set) var currentMode: LayoutMode?

    public init(monitorRect: Rect, config: TesseraConfig = TesseraConfig()) {
        self.monitorRect = monitorRect
        self.config = config
        self.nextSplit = config.initialSplit
    }

    // MARK: - Public API

    public func addWindow(_ window: Window) {
        let gap = config.gapSize / 2.0

        guard let currentRoot = root else {
            let usable = monitorRect.inset(by: config.outerGap)
            var w = window
            w.rect = usable.inset(by: gap)
            root = TreeNode(rect: usable, window: w, isFocused: true)
            return
        }

        let target = findLargestLeaf(currentRoot)
        let oldWindow = target.window!
        let oldRect = target.rect

        let splitDir: SplitType = target.rect.width >= target.rect.height ? .vertical : .horizontal
        let existingRect: Rect
        let newRect: Rect

        if splitDir == .vertical {
            let split = oldRect.splitVertical()
            existingRect = split.left
            newRect = split.right
        } else {
            let split = oldRect.splitHorizontal()
            existingRect = split.top
            newRect = split.bottom
        }

        let existingInset = existingRect.inset(by: gap)
        let newInset = newRect.inset(by: gap)

        var updatedExisting = oldWindow
        updatedExisting.rect = existingInset

        var updatedNew = window
        updatedNew.rect = newInset

        print("[bsp] add \(window.id) — split=\(splitDir) oldRect=\(oldRect) existing=\(existingRect)→\(existingInset) new=\(newRect)→\(newInset)")

        target.window = nil
        target.splitType = splitDir
        target.leftChild = TreeNode(rect: existingRect, window: updatedExisting, isFocused: !config.newWindowFocus)
        target.rightChild = TreeNode(rect: newRect, window: updatedNew, isFocused: config.newWindowFocus)
    }

    @discardableResult
    public func removeWindow(id: String) -> Window? {
        guard let currentRoot = root else { return nil }

        guard let (target, parent) = findPathToLeaf(currentRoot, windowId: id) else {
            return nil
        }

        let removed = target.window

        guard let parentNode = parent else {
            root = nil
            nextSplit = config.initialSplit
            return removed
        }

        let surviving: TreeNode
        if parentNode.leftChild === target {
            surviving = parentNode.rightChild!
        } else {
            surviving = parentNode.leftChild!
        }

        parentNode.window = surviving.window
        parentNode.rect = surviving.rect
        parentNode.leftChild = surviving.leftChild
        parentNode.rightChild = surviving.rightChild
        parentNode.splitType = surviving.splitType
        parentNode.isFocused = true

        return removed
    }

    @discardableResult
    public func focusWindow(id: String) -> Bool {
        clearFocus(root)
        return setFocusByID(root, windowId: id)
    }

    /// Flip the split orientation of the focused window's parent node
    /// (vertical ↔ horizontal) and reflow the subtree within the parent's rect.
    /// Returns false when the focused window has no parent split to toggle.
    @discardableResult
    public func toggleSplitDirection() -> Bool {
        guard let currentRoot = root,
              let focusedID = focusedWindowID,
              let (_, parent) = findPathToLeaf(currentRoot, windowId: focusedID),
              let parentNode = parent else { return false }

        let gap = config.gapSize / 2.0
        parentNode.splitType = parentNode.splitType == .vertical ? .horizontal : .vertical
        reflow(parentNode, in: parentNode.rect, gap: gap)
        print("[bsp] toggle split → \(parentNode.splitType?.description ?? "?") on \(parentNode.rect)")
        return true
    }

    /// Nudge the split ratio of the focused window's parent by `delta`, clamped
    /// to [config.splitMinRatio, config.splitMaxRatio], and reflow the subtree.
    /// A POSITIVE `delta` always grows the focused window's share (regardless
    /// of which side of the split it sits on); negative shrinks.
    /// Returns false when the focused window has no parent split to resize.
    @discardableResult
    public func resizeSplit(delta: Double) -> Bool {
        guard let currentRoot = root,
              let focusedID = focusedWindowID,
              let (_, parent) = findPathToLeaf(currentRoot, windowId: focusedID),
              let parentNode = parent else { return false }

        let gap = config.gapSize / 2.0
        let focusedIsFirst = containsWindowID(parentNode.leftChild, windowId: focusedID)
        let applied = focusedIsFirst ? delta : -delta
        let current = parentNode.ratio ?? 0.5
        let clamped = min(max(current + applied, config.splitMinRatio), config.splitMaxRatio)
        parentNode.ratio = clamped
        reflow(parentNode, in: parentNode.rect, gap: gap)
        print("[bsp] resize split → \(clamped) on \(parentNode.rect)")
        return true
    }

    /// Snapshot every internal node's split state (ratio + orientation), keyed by a
    /// node-identity string. The identity is `"<leftmost|<rightmost>"` of the
    /// node's direct children's leftmost leaf windows: unique per node and
    /// stable while those two leaves exist — so surviving splits keep their
    /// weights even when windows elsewhere in the tree are added or removed.
    /// Only meaningful in bsp mode (masterStack/columns ignore ratios).
    public func captureSplitState() -> [String: SplitState] {
        guard currentMode == .bsp else { return [:] }
        var states: [String: SplitState] = [:]
        forEachInternalNode(root) { node in
            guard let leftmost = leftmostLeafWindowID(node.leftChild),
                  let rightmost = leftmostLeafWindowID(node.rightChild) else { return }
            states["\(leftmost)|\(rightmost)"] = SplitState(
                ratio: node.ratio ?? 0.5,
                orientation: node.splitType ?? .vertical
            )
        }
        return states
    }

    /// Restore split states captured by `captureSplitState`. Nodes whose identity
    /// key is absent (new splits after an add, reshaped subtrees) keep the
    /// default 50/50 + geometry-derived orientation. Reflows the bsp tree so
    /// leaf geometry reflects the restored weights and orientations.
    public func applySplitState(_ states: [String: SplitState]) {
        guard currentMode == .bsp, root != nil, !states.isEmpty else { return }
        forEachInternalNode(root) { node in
            guard let leftmost = leftmostLeafWindowID(node.leftChild),
                  let rightmost = leftmostLeafWindowID(node.rightChild),
                  let state = states["\(leftmost)|\(rightmost)"] else { return }
            node.ratio = state.ratio
            node.splitType = state.orientation
        }
        let gap = config.gapSize / 2.0
        reflow(root, in: root!.rect, gap: gap)
    }

    private func forEachInternalNode(_ node: TreeNode?, _ body: (TreeNode) -> Void) {
        guard let node, !node.isLeaf else { return }
        forEachInternalNode(node.leftChild, body)
        body(node)
        forEachInternalNode(node.rightChild, body)
    }

    private func leftmostLeafWindowID(_ node: TreeNode?) -> String? {
        guard let node else { return nil }
        if let window = node.window { return window.id }
        return leftmostLeafWindowID(node.leftChild) ?? leftmostLeafWindowID(node.rightChild)
    }

    private func reflow(_ node: TreeNode?, in rect: Rect, gap: Double) {
        guard let node else { return }
        node.rect = rect
        if node.isLeaf {
            if var window = node.window {
                window.rect = rect.inset(by: gap)
                node.window = window
            }
            return
        }
        let dir = node.splitType ?? .vertical
        let ratio = node.ratio ?? 0.5
        if dir == .vertical {
            let split = rect.splitVertical(fraction: ratio)
            reflow(node.leftChild, in: split.left, gap: gap)
            reflow(node.rightChild, in: split.right, gap: gap)
        } else {
            let split = rect.splitHorizontal(fraction: ratio)
            reflow(node.leftChild, in: split.top, gap: gap)
            reflow(node.rightChild, in: split.bottom, gap: gap)
        }
    }

    public func getLayout() -> [(Window, Rect)] {
        var result: [(Window, Rect)] = []
        collectLeaves(root, result: &result)
        return result
    }

    /// (Re)build the display's tree for `mode` from the ordered window IDs,
    /// then pin windows to their leaf slots (`reassignLayoutOrder`). The tree
    /// is fully derived from the ordered list, so a re-tile rebuilds it the
    /// same way each time and window order continues to be preserved.
    public func applyPreset(_ mode: LayoutMode, orderedIDs: [String]) {
        currentMode = mode
        guard !orderedIDs.isEmpty else {
            root = nil
            return
        }
        let gap = config.gapSize / 2.0
        let usable = monitorRect.inset(by: config.outerGap)
        switch mode {
        case .bsp:
            root = nil
            for id in orderedIDs { addWindow(Window(id: id)) }
        case .masterStack:
            root = makeMasterStackTree(ids: orderedIDs, usable: usable)
        case .columns:
            root = makeColumnsTree(ids: orderedIDs, usable: usable)
        }
        if root == nil, let first = orderedIDs.first {
            var w = Window(id: first)
            w.rect = usable.inset(by: gap)
            root = TreeNode(rect: usable, window: w, isFocused: true)
        }
        reassignLayoutOrder(orderedIDs)
    }

    /// masterStack: master (first window) at `masterRatio` width on the left,
    /// the remainder as equal-height rows stacked in the right column.
    /// A single window fills the whole usable area (master only).
    private func makeMasterStackTree(ids: [String], usable: Rect) -> TreeNode? {
        guard let first = ids.first else { return nil }
        let rest = Array(ids.dropFirst())
        let masterWidth = rest.isEmpty ? usable.width : usable.width * config.masterRatio
        let masterRect = Rect(x: usable.x, y: usable.y, width: masterWidth, height: usable.height)
        let masterLeaf = TreeNode(rect: masterRect, window: Window(id: first), isFocused: true)
        guard !rest.isEmpty else { return masterLeaf }

        let stackRect = Rect(x: usable.x + masterWidth, y: usable.y, width: usable.width - masterWidth, height: usable.height)
        let rowHeight = stackRect.height / Double(rest.count)
        let rowLeaves: [TreeNode] = rest.enumerated().map { index, id in
            let r = Rect(x: stackRect.x, y: stackRect.y + rowHeight * Double(index), width: stackRect.width, height: rowHeight)
            return TreeNode(rect: r, window: Window(id: id), isFocused: false)
        }
        return combineBinary(rowLeaves, adding: masterLeaf, split: .vertical, whole: usable)
    }

    /// columns: every window as an equal-width, full-height column.
    private func makeColumnsTree(ids: [String], usable: Rect) -> TreeNode? {
        guard !ids.isEmpty else { return nil }
        let columnWidth = usable.width / Double(ids.count)
        let leaves: [TreeNode] = ids.enumerated().map { index, id in
            let r = Rect(x: usable.x + columnWidth * Double(index), y: usable.y, width: columnWidth, height: usable.height)
            return TreeNode(rect: r, window: Window(id: id), isFocused: index == 0)
        }
        return combineBinary(leaves, split: .vertical, whole: usable)
    }

    /// Fold `leaves` into a balanced binary tree using `whole` as every
    /// internal node's rect. `head` (if given) becomes the FIRST in-order leaf
    /// — it must be, because `reassignLayoutOrder` pins rank 0 to the first
    /// traversal leaf. Internal nodes are only used for traversal (focus
    /// search); leaf geometry is stored on the leaves themselves.
    private func combineBinary(_ leaves: [TreeNode], adding head: TreeNode? = nil, split: SplitType, whole: Rect) -> TreeNode {
        var nodes = leaves
        if let head { nodes = [head] + nodes }
        while nodes.count > 1 {
            var next: [TreeNode] = []
            var i = 0
            while i < nodes.count {
                let a = nodes[i]
                if i + 1 < nodes.count {
                    let b = nodes[i + 1]
                    next.append(TreeNode(rect: whole, leftChild: a, rightChild: b, splitType: split, isFocused: false))
                    i += 2
                } else {
                    next.append(a)
                    i += 1
                }
            }
            nodes = next
        }
        return nodes[0]
    }

    /// Reassigns leaf windows in in-order traversal to `orderedIDs`, preserving
    /// each leaf's geometry (its tile slot). This is what keeps windows in their
    /// slot across re-tiles: leaf geometry is order-invariant for a given window
    /// set, so assigning by rank pins each window to the same region.
    public func reassignLayoutOrder(_ orderedIDs: [String]) {
        guard !orderedIDs.isEmpty, root != nil else { return }
        let previousFocusedID = focusedWindowID
        var leaves: [TreeNode] = []
        collectLeafNodes(root, into: &leaves)
        let gap = config.gapSize / 2.0
        for (index, node) in leaves.enumerated() where index < orderedIDs.count {
            node.window = Window(id: orderedIDs[index], rect: node.rect.inset(by: gap))
        }
        // Focus lives on the leaf, not the window — restore it by id after renaming.
        if let previousFocusedID, orderedIDs.contains(previousFocusedID) {
            clearFocus(root)
            _ = setFocusByID(root, windowId: previousFocusedID)
        }
    }

    // MARK: - Cycle navigation

    @discardableResult
    public func cycleNext() -> Bool {
        let windows = getLayout()
        guard let currentID = focusedWindowID,
              let idx = windows.firstIndex(where: { $0.0.id == currentID }),
              windows.count > 1 else { return false }
        return focusWindow(id: windows[(idx + 1) % windows.count].0.id)
    }

    @discardableResult
    public func cyclePrev() -> Bool {
        let windows = getLayout()
        guard let currentID = focusedWindowID,
              let idx = windows.firstIndex(where: { $0.0.id == currentID }),
              windows.count > 1 else { return false }
        return focusWindow(id: windows[(idx - 1 + windows.count) % windows.count].0.id)
    }

    // MARK: - Focus navigation

    public var focusedWindowID: String? {
        guard let root else { return nil }
        return findFocusedLeaf(root).window?.id
    }

    @discardableResult
    public func focusLeft() -> Bool {
        let windows = getLayout()
        guard let currentID = focusedWindowID,
              let current = windows.first(where: { $0.0.id == currentID }) else { return false }

        let cur = current.1
        let cx = cur.x + cur.width / 2

        var best: (Window, Rect)? = nil
        var bestDist: Double = .greatestFiniteMagnitude
        var bestOverlap: Double = 0

        for (w, r) in windows {
            guard w.id != currentID else { continue }
            let rightEdge = r.x + r.width
            guard rightEdge <= cx else { continue }

            let dist = cx - rightEdge
            let overlap = max(0, min(cur.y + cur.height, r.y + r.height) - max(cur.y, r.y))
            let hasOverlap = overlap > 0

            if best == nil { best = (w, r); bestDist = dist; bestOverlap = overlap; continue }

            let bestHadOverlap = bestOverlap > 0
            guard !(!hasOverlap && bestHadOverlap) else { continue }
            guard !(hasOverlap == bestHadOverlap && dist > bestDist) else { continue }
            guard !(hasOverlap == bestHadOverlap && dist == bestDist && overlap <= bestOverlap) else { continue }

            best = (w, r); bestDist = dist; bestOverlap = overlap
        }

        guard let target = best else { return false }
        return focusWindow(id: target.0.id)
    }

    @discardableResult
    public func focusRight() -> Bool {
        let windows = getLayout()
        guard let currentID = focusedWindowID,
              let current = windows.first(where: { $0.0.id == currentID }) else { return false }

        let cur = current.1
        let cx = cur.x + cur.width / 2

        var best: (Window, Rect)? = nil
        var bestDist: Double = .greatestFiniteMagnitude
        var bestOverlap: Double = 0

        for (w, r) in windows {
            guard w.id != currentID else { continue }
            let leftEdge = r.x
            guard leftEdge >= cx else { continue }

            let dist = leftEdge - cx
            let overlap = max(0, min(cur.y + cur.height, r.y + r.height) - max(cur.y, r.y))
            let hasOverlap = overlap > 0

            if best == nil { best = (w, r); bestDist = dist; bestOverlap = overlap; continue }

            let bestHadOverlap = bestOverlap > 0
            guard !(!hasOverlap && bestHadOverlap) else { continue }
            guard !(hasOverlap == bestHadOverlap && dist > bestDist) else { continue }
            guard !(hasOverlap == bestHadOverlap && dist == bestDist && overlap <= bestOverlap) else { continue }

            best = (w, r); bestDist = dist; bestOverlap = overlap
        }

        guard let target = best else { return false }
        return focusWindow(id: target.0.id)
    }

    @discardableResult
    public func focusUp() -> Bool {
        let windows = getLayout()
        guard let currentID = focusedWindowID,
              let current = windows.first(where: { $0.0.id == currentID }) else { return false }

        let cur = current.1
        let cy = cur.y + cur.height / 2

        var best: (Window, Rect)? = nil
        var bestDist: Double = .greatestFiniteMagnitude
        var bestOverlap: Double = 0

        for (w, r) in windows {
            guard w.id != currentID else { continue }
            let bottomEdge = r.y + r.height
            guard bottomEdge <= cy else { continue }

            let dist = cy - bottomEdge
            let overlap = max(0, min(cur.x + cur.width, r.x + r.width) - max(cur.x, r.x))
            let hasOverlap = overlap > 0

            if best == nil { best = (w, r); bestDist = dist; bestOverlap = overlap; continue }

            let bestHadOverlap = bestOverlap > 0
            guard !(!hasOverlap && bestHadOverlap) else { continue }
            guard !(hasOverlap == bestHadOverlap && dist > bestDist) else { continue }
            guard !(hasOverlap == bestHadOverlap && dist == bestDist && overlap <= bestOverlap) else { continue }

            best = (w, r); bestDist = dist; bestOverlap = overlap
        }

        guard let target = best else { return false }
        return focusWindow(id: target.0.id)
    }

    @discardableResult
    public func focusDown() -> Bool {
        let windows = getLayout()
        guard let currentID = focusedWindowID,
              let current = windows.first(where: { $0.0.id == currentID }) else { return false }

        let cur = current.1
        let cy = cur.y + cur.height / 2

        var best: (Window, Rect)? = nil
        var bestDist: Double = .greatestFiniteMagnitude
        var bestOverlap: Double = 0

        for (w, r) in windows {
            guard w.id != currentID else { continue }
            let topEdge = r.y
            guard topEdge >= cy else { continue }

            let dist = topEdge - cy
            let overlap = max(0, min(cur.x + cur.width, r.x + r.width) - max(cur.x, r.x))
            let hasOverlap = overlap > 0

            if best == nil { best = (w, r); bestDist = dist; bestOverlap = overlap; continue }

            let bestHadOverlap = bestOverlap > 0
            guard !(!hasOverlap && bestHadOverlap) else { continue }
            guard !(hasOverlap == bestHadOverlap && dist > bestDist) else { continue }
            guard !(hasOverlap == bestHadOverlap && dist == bestDist && overlap <= bestOverlap) else { continue }

            best = (w, r); bestDist = dist; bestOverlap = overlap
        }

        guard let target = best else { return false }
        return focusWindow(id: target.0.id)
    }

    // MARK: - Internal

    public func findFocusedLeaf(_ node: TreeNode) -> TreeNode {
        guard !node.isLeaf else { return node }
        let candidate = findFocusedLeaf(node.leftChild!)
        if candidate.isFocused { return candidate }
        return findFocusedLeaf(node.rightChild!)
    }

    public func findLargestLeaf(_ node: TreeNode) -> TreeNode {
        guard !node.isLeaf else { return node }
        let left = findLargestLeaf(node.leftChild!)
        let right = findLargestLeaf(node.rightChild!)
        let leftArea = left.rect.width * left.rect.height
        let rightArea = right.rect.width * right.rect.height
        return leftArea >= rightArea ? left : right
    }

    private func findPathToLeaf(_ node: TreeNode?, windowId: String, parent: TreeNode? = nil) -> (target: TreeNode, parent: TreeNode?)? {
        guard let node else { return nil }
        if node.isLeaf {
            if node.window?.id == windowId {
                return (node, parent)
            }
            return nil
        }
        if let leftResult = findPathToLeaf(node.leftChild, windowId: windowId, parent: node) {
            return leftResult
        }
        return findPathToLeaf(node.rightChild, windowId: windowId, parent: node)
    }

    /// True when the subtree rooted at `node` (directly or transitively) holds
    /// the window `windowId`.
    private func containsWindowID(_ node: TreeNode?, windowId: String) -> Bool {
        guard let node else { return false }
        if node.isLeaf { return node.window?.id == windowId }
        return containsWindowID(node.leftChild, windowId: windowId)
            || containsWindowID(node.rightChild, windowId: windowId)
    }

    private func clearFocus(_ node: TreeNode?) {
        guard let node else { return }
        node.isFocused = false
        clearFocus(node.leftChild)
        clearFocus(node.rightChild)
    }

    @discardableResult
    private func setFocusByID(_ node: TreeNode?, windowId: String) -> Bool {
        guard let node else { return false }
        if node.isLeaf {
            if node.window?.id == windowId {
                node.isFocused = true
                return true
            }
            return false
        }
        if setFocusByID(node.leftChild, windowId: windowId) { return true }
        return setFocusByID(node.rightChild, windowId: windowId)
    }

    private func collectLeaves(_ node: TreeNode?, result: inout [(Window, Rect)]) {
        guard let node else { return }
        if node.isLeaf, let window = node.window, let winRect = window.rect {
            result.append((window, winRect))
            return
        }
        collectLeaves(node.leftChild, result: &result)
        collectLeaves(node.rightChild, result: &result)
    }

    private func collectLeafNodes(_ node: TreeNode?, into result: inout [TreeNode]) {
        guard let node else { return }
        if node.isLeaf {
            result.append(node)
            return
        }
        collectLeafNodes(node.leftChild, into: &result)
        collectLeafNodes(node.rightChild, into: &result)
    }
}
