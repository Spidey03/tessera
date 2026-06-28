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

    public func splitHorizontal() -> (top: Rect, bottom: Rect) {
        let halfHeight = height / 2
        let top = Rect(x: x, y: y, width: width, height: halfHeight)
        let bottom = Rect(x: x, y: y + halfHeight, width: width, height: halfHeight)
        return (top, bottom)
    }

    public func splitVertical() -> (left: Rect, right: Rect) {
        let halfWidth = width / 2
        let left = Rect(x: x, y: y, width: halfWidth, height: height)
        let right = Rect(x: x + halfWidth, y: y, width: halfWidth, height: height)
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
