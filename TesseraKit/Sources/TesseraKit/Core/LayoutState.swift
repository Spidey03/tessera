import Foundation

/// A window's absolute float frame (top-left origin, like AX) on `displayID`.
public struct FloatRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var displayID: UInt32

    public init(x: Double, y: Double, width: Double, height: Double, displayID: UInt32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.displayID = displayID
    }

    public init(from rect: Rect, displayID: UInt32) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height, displayID: displayID)
    }

    public var rect: Rect {
        Rect(x: x, y: y, width: width, height: height)
    }
}

/// Persistent per-display + per-window state (`state.json` next to
/// `config.json`).
///
/// Display IDs are `CGDirectDisplayID` values (UInt32) serialized as decimal
/// strings, so unplugged monitors can be pruned without ever mingling two
/// monitors' entries. All keys are optional — an older `state.json` holding
/// just `displayModes` still decodes, and full state round-trips losslessly.
public struct LayoutState: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case displayModes, floatRects, splitStates
    }

    /// Layout mode overrides keyed by decimal display ID. Entries not present
    /// fall back to `config.layoutMode`.
    public var displayModes: [String: LayoutMode]

    /// Split states keyed by decimal display ID → node-identity key → state.
    /// A node's identity key is `"leftmost|rightmost"` of its direct children's
    /// leftmost leaves, unique per node and stable across adds/removes elsewhere
    /// in the tree (see `Workspace.captureSplitState`).
    public var splitStates: [String: [String: SplitState]]

    /// Absolute float frames for windows keyed by `"appName|title"`.
    public var floatRects: [String: FloatRect]

    public init(displayModes: [String: LayoutMode] = [:],
                splitStates: [String: [String: SplitState]] = [:],
                floatRects: [String: FloatRect] = [:]) {
        self.displayModes = displayModes
        self.splitStates = splitStates
        self.floatRects = floatRects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayModes = try c.decodeIfPresent([String: LayoutMode].self, forKey: .displayModes) ?? [:]
        splitStates = try c.decodeIfPresent([String: [String: SplitState]].self, forKey: .splitStates) ?? [:]
        floatRects = try c.decodeIfPresent([String: FloatRect].self, forKey: .floatRects) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayModes, forKey: .displayModes)
        try c.encode(splitStates, forKey: .splitStates)
        try c.encode(floatRects, forKey: .floatRects)
    }

    /// The effective mode for a display: its override, else `fallback`.
    public func mode(for displayID: UInt32, fallback: LayoutMode) -> LayoutMode {
        displayModes[String(displayID)] ?? fallback
    }

    /// Set the override for a display (`nil` clears it to use the fallback).
    public mutating func setMode(_ mode: LayoutMode?, for displayID: UInt32) {
        if let mode {
            displayModes[String(displayID)] = mode
        } else {
            displayModes.removeValue(forKey: String(displayID))
        }
    }

    /// Saved split states for a display (splitStates[displayID]).
    public func splitStates(for displayID: UInt32) -> [String: SplitState] {
        splitStates[String(displayID)] ?? [:]
    }

    /// Set the saved split states for a display (empty removes it).
    public mutating func setSplitStates(_ states: [String: SplitState], for displayID: UInt32) {
        if states.isEmpty {
            splitStates.removeValue(forKey: String(displayID))
        } else {
            splitStates[String(displayID)] = states
        }
    }

    /// Saved float frame for a window key, if any.
    public func floatRect(for windowKey: String) -> FloatRect? {
        floatRects[windowKey]
    }

    /// Replace the saved float frames wholesale (called after each tile with
    /// the live floaters, so stale keys never accumulate).
    public mutating func setFloatRects(_ rects: [String: FloatRect]) {
        floatRects = rects
    }

    /// Drop overrides whose display is no longer live (monitor unplugged).
    public mutating func prune(liveDisplayIDs: Set<UInt32>) {
        let live = Set(liveDisplayIDs.map(String.init))
        displayModes = displayModes.filter { live.contains($0.key) }
        splitStates = splitStates.filter { live.contains($0.key) }
    }
}

/// Loads and saves `LayoutState` to a JSON file.
public enum LayoutStateStore {
    /// Loads the state file; missing or unparseable files yield an empty state.
    public static func load(from url: URL) -> LayoutState {
        guard let data = try? Data(contentsOf: url) else { return LayoutState() }
        return (try? JSONDecoder().decode(LayoutState.self, from: data)) ?? LayoutState()
    }

    /// Atomically writes the state file, creating the directory if needed.
    public static func save(_ state: LayoutState, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }
}