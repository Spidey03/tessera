import CoreGraphics
import Foundation
import TesseraKit

// MARK: - Config file models

struct HotkeyConfig: Codable {
    var keyCode: UInt16
    var flags: [String]
}

struct MultiMonitorConfigFile: Codable {
    var focusMode: String?
}

struct TesseraConfigFile: Codable {
    var gapSize: Double?
    var outerGap: Double?
    var newWindowFocus: Bool?
    var floatingApps: [String]?
    var animationEnabled: Bool?
    var animationSteps: Int?
    var animationDuration: Double?
    var multiMonitor: MultiMonitorConfigFile?
    var appRules: [String: AppTilingRule]?
    var hotkeys: [String: HotkeyConfig]?
}

// MARK: - Loaded config

struct LoadedConfig {
    var tesseraConfig: TesseraConfig
    var bindings: [KeyBinding]
}

// MARK: - Loader

enum ConfigLoader {
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/tessera")
    private static let configPath = configDir.appendingPathComponent("config.json")

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
                "newWindowFocus": false,
                // Legacy key: still supported for backward compatibility (auto-migrated to appRules)
                "floatingApps": ["com.spotify.client"],
                // Per-app tiling rules (preferred; supersedes floatingApps for these bundle IDs)
                "appRules": [
                    "com.spotify.client": "float",
                    "com.apple.Safari": "normal",
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
            newWindowFocus: fc.newWindowFocus ?? defaults.newWindowFocus,
            floatingAppIDs: fc.floatingApps ?? defaults.floatingAppIDs,
            appRules: mergedAppRules,
            animationEnabled: fc.animationEnabled ?? defaults.animationEnabled,
            animationSteps: fc.animationSteps ?? defaults.animationSteps,
            animationDuration: fc.animationDuration ?? defaults.animationDuration,
            multiMonitor: MultiMonitorConfig(
                focusMode: fc.multiMonitor?.focusMode ?? MultiMonitorConfig().focusMode
            )
        )
    }

    static func defaultBindings() -> [KeyBinding] {
        [
            KeyBinding(keyCode: 36, flags: [.maskCommand, .maskAlternate], action: "tile"),
            KeyBinding(keyCode: 4, flags: [.maskCommand, .maskAlternate], action: "focusLeft"),
            KeyBinding(keyCode: 37, flags: [.maskCommand, .maskAlternate], action: "focusRight"),
            KeyBinding(keyCode: 40, flags: [.maskCommand, .maskAlternate], action: "focusLeft"),
            KeyBinding(keyCode: 38, flags: [.maskCommand, .maskAlternate], action: "focusRight"),
            KeyBinding(keyCode: 13, flags: [.maskCommand, .maskAlternate], action: "remove"),
            KeyBinding(keyCode: 34, flags: [.maskCommand, .maskAlternate], action: "focusUp"),      // I
            KeyBinding(keyCode: 46, flags: [.maskCommand, .maskAlternate], action: "focusDown"),    // M
            KeyBinding(keyCode: 3, flags: [.maskCommand, .maskAlternate], action: "fullscreen"),
            KeyBinding(keyCode: 49, flags: [.maskCommand, .maskAlternate], action: "toggleSplit"), // Space
            KeyBinding(keyCode: 12, flags: [.maskCommand, .maskAlternate, .maskShift], action: "quit"),
        ]
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

    private static func mergeBindings(_ hotkeys: [String: HotkeyConfig]?) -> [KeyBinding] {
        guard let hotkeys = hotkeys, !hotkeys.isEmpty else { return defaultBindings() }
        var result = defaultBindings()
        for (actionName, hotkey) in hotkeys {
            let flags = parseFlags(hotkey.flags)
            let binding = KeyBinding(keyCode: hotkey.keyCode, flags: flags, action: actionName)
            result.removeAll { $0.keyCode == hotkey.keyCode }
            result.append(binding)
        }
        return result
    }
}
