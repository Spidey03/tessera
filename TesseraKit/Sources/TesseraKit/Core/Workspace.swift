public final class Workspace: @unchecked Sendable {
    public let monitorRect: Rect
    public let config: TesseraConfig
    public private(set) var root: TreeNode?
    public private(set) var nextSplit: SplitType

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

    public func getLayout() -> [(Window, Rect)] {
        var result: [(Window, Rect)] = []
        collectLeaves(root, result: &result)
        return result
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
}
