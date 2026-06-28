public struct Window: Equatable, Sendable {
    public let id: String
    public var rect: Rect?

    public init(id: String, rect: Rect? = nil) {
        self.id = id
        self.rect = rect
    }
}

extension Window: CustomStringConvertible {
    public var description: String {
        "Window(id=\(id), rect=\(rect.map(\.description) ?? "nil"))"
    }
}
