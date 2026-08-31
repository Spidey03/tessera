/// How a specific app is treated by the tiler.
public enum AppTilingRule: Equatable, Codable, Sendable {
    /// Window enters the BSP tree normally (default for all apps).
    case normal
    /// Window is never tiled — stays at its current position/size. Completely invisible to the tiler.
    case ignore
    /// Window never enters the BSP tree; treated like a floating app (current `floatingAppIDs` behavior).
    case float
    
    /// Check if this rule means the window should be excluded from the BSP layout.
    public var excludesFromLayout: Bool {
        switch self {
        case .normal: return false
        case .ignore, .float: return true
        }
    }
}
