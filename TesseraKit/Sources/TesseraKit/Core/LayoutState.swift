import Foundation

/// Persistent per-display layout configuration (`state.json` next to
/// `config.json`).
///
/// Display IDs are `CGDirectDisplayID` values (UInt32) serialized as decimal
/// strings, so unplugged monitors can be pruned without ever mingling two
/// monitors' overrides. An override makes that display use a layout mode
/// different from `config.layoutMode`; restarting or reloading the daemon
/// restores it from `LayoutStateStore`.
public struct LayoutState: Codable, Sendable, Equatable {
    /// Layout mode overrides keyed by decimal display ID. Entries not present
    /// fall back to `config.layoutMode`.
    public var displayModes: [String: LayoutMode]

    public init(displayModes: [String: LayoutMode] = [:]) {
        self.displayModes = displayModes
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

    /// Drop overrides whose display is no longer live (monitor unplugged).
    public mutating func prune(liveDisplayIDs: Set<UInt32>) {
        displayModes = displayModes.filter { liveDisplayIDs.contains(UInt32($0.key) ?? 0) }
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