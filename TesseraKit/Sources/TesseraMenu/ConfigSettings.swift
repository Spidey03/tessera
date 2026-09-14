import AppKit
import Foundation
import TesseraKit

/// In-memory editing session for `~/.config/tessera/config.json`.
///
/// Loads the file (or `TesseraConfig()` defaults if absent), edits the
/// keys this UI knows about, and writes the file back while preserving
/// every key the UI does not edit (`hotkeys`, `excludedSubroles`,
/// `multiMonitor`, `floatingApps`, ...).
final class ConfigSettings {
    private let configURL: URL
    private var dict: [String: Any]
    private let defaults = TesseraConfig()

    /// One row in the per-app rules editor. `bundleID` empty = row ignored on save.
    struct AppRule {
        var bundleID: String
        var rule: AppTilingRule

        init(bundleID: String, rule: AppTilingRule) {
            self.bundleID = bundleID
            self.rule = rule
        }
    }

    init(configURL: URL) {
        self.configURL = configURL
        if let data = try? Data(contentsOf: configURL),
           let object = try? JSONSerialization.jsonObject(with: data),
           let root = object as? [String: Any] {
            dict = root
        } else {
            dict = [:]
        }
    }

    private func number(_ key: String) -> NSNumber? {
        dict[key] as? NSNumber
    }

    var gapSize: Double {
        get { number("gapSize")?.doubleValue ?? defaults.gapSize }
        set { dict["gapSize"] = newValue }
    }

    var outerGap: Double {
        get { number("outerGap")?.doubleValue ?? defaults.outerGap }
        set { dict["outerGap"] = newValue }
    }

    var newWindowFocus: Bool {
        get { dict["newWindowFocus"] as? Bool ?? defaults.newWindowFocus }
        set { dict["newWindowFocus"] = newValue }
    }

    var animationEnabled: Bool {
        get { dict["animationEnabled"] as? Bool ?? defaults.animationEnabled }
        set { dict["animationEnabled"] = newValue }
    }

    var animationSteps: Int {
        get { number("animationSteps")?.intValue ?? defaults.animationSteps }
        set { dict["animationSteps"] = max(1, min(60, newValue)) }
    }

    var animationDuration: Double {
        get { number("animationDuration")?.doubleValue ?? defaults.animationDuration }
        set { dict["animationDuration"] = newValue }
    }

    /// App rules as a sorted list (keys `appRules` in config JSON map to `"normal"`,
    /// `"ignore"`, `"float"`, `"sticky"`).
    var appRules: [String: AppTilingRule] {
        get {
            guard let raw = dict["appRules"] as? [String: String] else {
                return defaults.appRules
            }
            var result: [String: AppTilingRule] = [:]
            for (bundleID, value) in raw {
                if let rule = AppTilingRule(rawValue: value) {
                    result[bundleID] = rule
                }
            }
            return result
        }
        set {
            var raw: [String: String] = [:]
            for (bundleID, rule) in newValue where !bundleID.isEmpty {
                raw[bundleID] = rule.rawValue
            }
            dict["appRules"] = raw
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            let fm = FileManager.default
            let dir = configURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: configURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}