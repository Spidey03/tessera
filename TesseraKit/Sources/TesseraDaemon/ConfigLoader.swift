import CoreGraphics
import Foundation
import TesseraKit

// MARK: - Config file models

struct MultiMonitorConfigFile: Codable {
    var focusMode: String?
}

struct TesseraConfigFile: Codable {
    var gapSize: Double?
    var outerGap: Double?
    var layoutMode: String?
    var masterRatio: Double?
    var splitResizeStep: Double?
    var splitMinRatio: Double?
    var splitMaxRatio: Double?
    var newWindowFocus: Bool?
    var floatingApps: [String]?
    var animationEnabled: Bool?
    var animationSteps: Int?
    var animationDuration: Double?
    var multiMonitor: MultiMonitorConfigFile?
    var appRules: [String: AppTilingRule]?
    var excludedSubroles: [String]?
    var hotkeys: [String: HotkeySpec]?
}

// MARK: - Loaded config

struct LoadedConfig {
    var tesseraConfig: TesseraConfig
    var bindings: [KeyBinding]
}

// MARK: - Loader

enum ConfigLoader {
    /// Directory holding config.json, state.json, and (optionally) the example config.
    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/tessera")
    private static let configPath = configDir.appendingPathComponent("config.json")
    /// Per-display layout state persisted by the daemon (see LayoutState).
    static let statePath = configDir.appendingPathComponent("state.json")

    static func load() -> LoadedConfig {
        let fileConfig: TesseraConfigFile?
        if FileManager.default.fileExists(atPath: configPath.path) {
            do {
                let data = try Data(contentsOf: configPath)
                fileConfig = try JSONDecoder().decode(TesseraConfigFile.self, from: data)
                print("[config] loaded from \(configPath.path)")
            } catch {
                print("[config] WARNING: failed to parse \(configPath.path): \(error)")
                print("[config] falling back to defaults")
                fileConfig = nil
            }
        } else {
            print("[config] no config file at \(configPath.path) — using defaults")
            fileConfig = nil
        }

        let tesseraConfig = mergeConfig(fileConfig)
        let bindings = mergeBindings(fileConfig?.hotkeys)

        return LoadedConfig(tesseraConfig: tesseraConfig, bindings: bindings)
    }

    // MARK: - Example config

    static func ensureConfigDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir.path) {
            try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: configPath.path) {
            let example: [String: Any] = [
                "gapSize": 8.0,
                "outerGap": 4.0,
                // Layout algorithm applied at startup: bsp | masterStack | columns.
                // This is the DEFAULT for every display; per-display overrides
                // (via the cycleLayout hotkey / "setLayout" IPC) persist to state.json.
                "layoutMode": "bsp",
                // Fraction of screen width given to the master pane in masterStack.
                "masterRatio": 0.6,
                // How much one resize hotkey press (⌘⌥[ / ⌘⌥]) moves a bsp split,
                // and the range split ratios are clamped to (0…1).
                "splitResizeStep": 0.10,
                "splitMinRatio": 0.2,
                "splitMaxRatio": 0.8,
                "newWindowFocus": false,
                // Legacy key: still supported for backward compatibility (auto-migrated to appRules)
                "floatingApps": ["com.spotify.client"],
                // Per-app tiling rules (preferred; supersedes floatingApps for these bundle IDs):
                //   normal — tiled (default)
                //   float  — excluded from BSP, keeps its own position/size
                //   ignore — completely untouched and invisible to the tiler
                //   sticky — tiled, but keeps its tile slot across re-tiles
                "appRules": [
                    "com.spotify.client": "float",
                    "com.apple.Safari": "normal",
                    "com.apple.Notes": "sticky",
                ],
                // Window subroles never tiled. If present, this REPLACES the built-in set.
                "excludedSubroles": [
                    "AXDialog", "AXSystemDialog",
                    "AXSheet", "AXSystemSheet",
                    "AXFloatingWindow", "AXSystemFloatingWindow",
                    "AXStatusWindow", "AXSystemStatusWindow",
                    "AXHelpWindow", "AXPopover",
                ],
                "animationEnabled": true,
                "animationSteps": 8,
                "animationDuration": 0.15,
                "multiMonitor": [
                    "focusMode": "withinDisplay",
                ],
                "hotkeys": [
                    "tile": ["keyCode": 36, "flags": ["cmd", "opt"]],
                    "focusLeft": ["keyCode": 4, "flags": ["cmd", "opt"]],
                    "focusRight": ["keyCode": 37, "flags": ["cmd", "opt"]],
                    "remove": ["keyCode": 13, "flags": ["cmd", "opt"]],
                    "focusUp": ["keyCode": 34, "flags": ["cmd", "opt"]],
                    "focusDown": ["keyCode": 46, "flags": ["cmd", "opt"]],
                    "fullscreen": ["keyCode": 3, "flags": ["cmd", "opt"]],
                    "toggleSplit": ["keyCode": 49, "flags": ["cmd", "opt"]],
                    "resizeShrink": ["keyCode": 33, "flags": ["cmd", "opt"]],
                    "resizeGrow": ["keyCode": 30, "flags": ["cmd", "opt"]],
                    "cycleLayout": ["keyCode": 47, "flags": ["cmd", "opt"]],
                    "quit": ["keyCode": 12, "flags": ["cmd", "opt", "shift"]],
                ],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: example, options: [.prettyPrinted, .withoutEscapingSlashes]),
               let json = String(data: data, encoding: .utf8) {
                try? json.write(to: configPath, atomically: true, encoding: .utf8)
                print("[config] wrote example config to \(configPath.path)")
            }
        }
    }

    // MARK: - Merging

    private static func mergeConfig(_ fileConfig: TesseraConfigFile?) -> TesseraConfig {
        guard let fc = fileConfig else { return TesseraConfig() }

        // Auto-migrate legacy floatingApps entries into appRules as .float rules.
        var mergedAppRules: [String: AppTilingRule] = fc.appRules ?? [:]
        for bundleID in fc.floatingApps ?? [] {
            if mergedAppRules[bundleID] == nil {
                mergedAppRules[bundleID] = .float
            }
        }

        let defaults = TesseraConfig()

        return TesseraConfig(
            gapSize: fc.gapSize ?? defaults.gapSize,
            outerGap: fc.outerGap ?? defaults.outerGap,
            layoutMode: parseLayoutMode(fc.layoutMode) ?? defaults.layoutMode,
            masterRatio: fc.masterRatio ?? defaults.masterRatio,
            splitResizeStep: fc.splitResizeStep ?? defaults.splitResizeStep,
            splitMinRatio: fc.splitMinRatio ?? defaults.splitMinRatio,
            splitMaxRatio: fc.splitMaxRatio ?? defaults.splitMaxRatio,
            newWindowFocus: fc.newWindowFocus ?? defaults.newWindowFocus,
            floatingAppIDs: fc.floatingApps ?? defaults.floatingAppIDs,
            appRules: mergedAppRules,
            excludedSubroles: fc.excludedSubroles ?? Array(AXSubrole.excludedDefaults).sorted(),
            animationEnabled: fc.animationEnabled ?? defaults.animationEnabled,
            animationSteps: fc.animationSteps ?? defaults.animationSteps,
            animationDuration: fc.animationDuration ?? defaults.animationDuration,
            multiMonitor: MultiMonitorConfig(
                focusMode: fc.multiMonitor?.focusMode ?? MultiMonitorConfig().focusMode
            )
        )
    }

    /// Parse the `"layoutMode"` string. Unknown values warn and return nil
    /// (caller falls back to the default `bsp`).
    private static func parseLayoutMode(_ raw: String?) -> LayoutMode? {
        guard let raw, let mode = LayoutMode(rawValue: raw) else {
            if let raw { print("[config] WARNING: unknown layoutMode '\(raw)' — using bsp") }
            return nil
        }
        return mode
    }

    static func defaultBindings() -> [KeyBinding] {
        HotkeyBindings.defaults.map { loadBinding(from: $0) }
    }

    /// Resolve a shared hotkey binding to the daemon's CGEvent-matching form.
    private static func loadBinding(from binding: HotkeyBinding) -> KeyBinding {
        KeyBinding(keyCode: binding.keyCode, flags: parseFlags(binding.flags), action: binding.action)
    }

    private static func parseFlags(_ strings: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for s in strings {
            switch s.lowercased() {
            case "cmd", "command": flags.insert(.maskCommand)
            case "opt", "alt", "option": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            case "caps", "capslock": flags.insert(.maskAlphaShift)
            default: print("[config] WARNING: unknown flag '\(s)' — ignoring")
            }
        }
        return flags
    }

    private static func mergeBindings(_ hotkeys: [String: HotkeySpec]?) -> [KeyBinding] {
        HotkeyBindings.merge(defaults: HotkeyBindings.defaults, overrides: hotkeys)
            .map { loadBinding(from: $0) }
    }
}
