public enum SplitType: Equatable, Sendable {
    case horizontal
    case vertical

    public func alternated() -> SplitType {
        switch self {
        case .horizontal: .vertical
        case .vertical: .horizontal
        }
    }
}

extension SplitType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .horizontal: "H"
        case .vertical: "V"
        }
    }
}
