public final class TreeNode: @unchecked Sendable {
    public var rect: Rect
    public var window: Window?
    public var leftChild: TreeNode?
    public var rightChild: TreeNode?
    public var splitType: SplitType?
    public var isFocused: Bool
    /// Share of the rect given to the FIRST child (left for vertical, top for
    /// horizontal). nil = 50/50 (the default). Only meaningful on internal nodes.
    public var ratio: Double?

    public var isLeaf: Bool {
        leftChild == nil && rightChild == nil
    }

    public init(
        rect: Rect,
        window: Window? = nil,
        leftChild: TreeNode? = nil,
        rightChild: TreeNode? = nil,
        splitType: SplitType? = nil,
        isFocused: Bool = false,
        ratio: Double? = nil
    ) {
        self.rect = rect
        self.window = window
        self.leftChild = leftChild
        self.rightChild = rightChild
        self.splitType = splitType
        self.isFocused = isFocused
        self.ratio = ratio
    }
}

extension TreeNode: CustomStringConvertible {
    public var description: String {
        if isLeaf {
            let w = window.map { "window=\($0.id)" } ?? "no-window"
            return "Leaf(\(w), rect=\(rect), focused=\(isFocused))"
        }
        return "Node(\(splitType.map(\.description) ?? "?"), left=\(leftChild.map(\.description) ?? "nil"), right=\(rightChild.map(\.description) ?? "nil"))"
    }
}
