public struct Rect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Split into top/bottom halves. `fraction` is the share given to the top
    /// (0…1). Default 0.5 keeps the legacy equal-split behavior.
    public func splitHorizontal(fraction: Double = 0.5) -> (top: Rect, bottom: Rect) {
        let topHeight = height * min(max(fraction, 0), 1)
        let top = Rect(x: x, y: y, width: width, height: topHeight)
        let bottom = Rect(x: x, y: y + topHeight, width: width, height: height - topHeight)
        return (top, bottom)
    }

    /// Split into left/right halves. `fraction` is the share given to the left
    /// (0…1). Default 0.5 keeps the legacy equal-split behavior.
    public func splitVertical(fraction: Double = 0.5) -> (left: Rect, right: Rect) {
        let leftWidth = width * min(max(fraction, 0), 1)
        let left = Rect(x: x, y: y, width: leftWidth, height: height)
        let right = Rect(x: x + leftWidth, y: y, width: width - leftWidth, height: height)
        return (left, right)
    }

    public func inset(by amount: Double) -> Rect {
        Rect(
            x: x + amount,
            y: y + amount,
            width: width - 2 * amount,
            height: height - 2 * amount
        )
    }
}

extension Rect: CustomStringConvertible {
    public var description: String {
        "Rect(x=\(Int(x.rounded())), y=\(Int(y.rounded())), w=\(Int(width.rounded())), h=\(Int(height.rounded())))"
    }
}
