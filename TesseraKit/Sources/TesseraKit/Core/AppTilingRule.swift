/// How a specific app is treated by the tiler.
/// A `String` raw type makes Codable encode/decode as the case name
/// (`"normal"`, `"ignore"`, `"float"`, `"sticky"`), matching config JSON.
public enum AppTilingRule: String, Equatable, Codable, Sendable {
    /// Window enters the BSP tree normally (default for all apps).
    case normal
    /// Window is never tiled — stays at its current position/size. Completely invisible to the tiler.
    case ignore
    /// Window never enters the BSP tree; treated like a floating app (current `floatingAppIDs` behavior).
    case float
    /// Window is tiled normally but keeps its tile slot across re-tiles (never re-ranked).
    case sticky

    /// Check if this rule means the window should be excluded from the BSP layout.
    public var excludesFromLayout: Bool {
        switch self {
        case .normal, .sticky: return false
        case .ignore, .float: return true
        }
    }
}
