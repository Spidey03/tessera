import Foundation

/// A hotkey override as stored in config.json under `"hotkeys"`:
/// `[actionName: {keyCode, flags}]`.
public struct HotkeySpec: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var flags: [String]

    public init(keyCode: UInt16, flags: [String]) {
        self.keyCode = keyCode
        self.flags = flags
    }
}

/// A single resolved hotkey: the action it triggers plus the combo
/// (keyCode + modifier flag names). Produced by merging config overrides
/// onto the built-in defaults.
public struct HotkeyBinding: Codable, Hashable, Sendable {
    public var action: String
    public var keyCode: UInt16
    public var flags: [String]

    public init(action: String, keyCode: UInt16, flags: [String]) {
        self.action = action
        self.keyCode = keyCode
        self.flags = flags
    }

    /// Human-readable combo, e.g. `"⌘⌥⏎"` or `"⌘⇧Q"`. Modifier order is
    /// ctrl, option, shift, command, fn, caps (matches the README's ⌘⌥[).
    public var display: String {
        HotkeyBindings.symbols(for: flags) + HotkeyBindings.keySymbol(for: keyCode)
    }
}

/// The canonical hotkey set and the merge logic shared by the daemon
/// (dispatch + reload), the Settings UI (editing), and the test suite.
public enum HotkeyBindings {
    /// Actions surfaced in the Settings UI. Every binding in `defaults`
    /// dispatches one of these (focusLeft/focusRight have two defaults each:
    /// the H/L vim keys plus K/J aliases).
    public static let canonicalActions: [String] = [
        "tile", "focusLeft", "focusRight", "focusUp", "focusDown",
        "cycleNext", "cyclePrev", "remove", "fullscreen",
        "toggleSplit", "resizeShrink", "resizeGrow", "cycleLayout", "quit",
    ]

    /// Built-in bindings. Modifier aliases in `normalizedFlags` are already
    /// resolved to canonical (`"opt"`, not `"alt"`; `"cmd"`, not `"command"`).
    public static let defaults: [HotkeyBinding] = [
        HotkeyBinding(action: "tile", keyCode: 36, flags: ["cmd", "opt"]),        // Return
        HotkeyBinding(action: "quit", keyCode: 12, flags: ["cmd", "opt", "shift"]), // Q
        HotkeyBinding(action: "focusLeft", keyCode: 4, flags: ["cmd", "opt"]),    // H
        HotkeyBinding(action: "focusLeft", keyCode: 40, flags: ["cmd", "opt"]),   // K — vim previous, aliased to focus left
        HotkeyBinding(action: "focusRight", keyCode: 37, flags: ["cmd", "opt"]),  // L
        HotkeyBinding(action: "focusRight", keyCode: 38, flags: ["cmd", "opt"]),  // J — vim next, aliased to focus right
        HotkeyBinding(action: "focusUp", keyCode: 34, flags: ["cmd", "opt"]),     // I
        HotkeyBinding(action: "focusDown", keyCode: 46, flags: ["cmd", "opt"]),   // M
        HotkeyBinding(action: "remove", keyCode: 13, flags: ["cmd", "opt"]),      // W
        HotkeyBinding(action: "cycleNext", keyCode: 125, flags: ["cmd", "opt"]),  // Down arrow
        HotkeyBinding(action: "cyclePrev", keyCode: 126, flags: ["cmd", "opt"]),  // Up arrow
        HotkeyBinding(action: "fullscreen", keyCode: 3, flags: ["cmd", "opt"]),   // F
        HotkeyBinding(action: "resizeShrink", keyCode: 33, flags: ["cmd", "opt"]), // [
        HotkeyBinding(action: "resizeGrow", keyCode: 30, flags: ["cmd", "opt"]),  // ]
        HotkeyBinding(action: "cycleLayout", keyCode: 47, flags: ["cmd", "opt"]), // Period
    ]

    /// The current action->default combo map (single binding per action;
    /// arbitrary for actions with aliases but stable ordering by keyCode).
    public static func defaultDisplay(for action: String) -> String? {
        defaults.filter { $0.action == action }
            .sorted { $0.keyCode < $1.keyCode }
            .first?
            .display
    }

    /// Merge `overrides` (from config.json `"hotkeys"`) onto `defaults`.
    ///
    /// Binds each override action to its combo. The claimed key is freed from
    /// whoever else used it — so a new `cycleLayout` on ⌘⌥T stops `tile` on
    /// that key if it was taken — but aliases already bound to the same action
    /// under *other* keys persist (e.g. overriding `focusLeft` keeps the K
    /// alias). Overrides are processed in action order so a key shared by two
    /// overrides goes to the later one deterministically.
    public static func merge(defaults: [HotkeyBinding],
                             overrides: [String: HotkeySpec]?) -> [HotkeyBinding] {
        var result = defaults
        guard let overrides, !overrides.isEmpty else { return result }
        for (action, spec) in overrides.sorted(by: { $0.key < $1.key }) {
            let flags = normalizedFlags(spec.flags)
            // A combinator-free override would match every bare-key event and
            // swallow it globally; ignore it instead of honoring it.
            guard !flags.isEmpty else { continue }
            result.removeAll { $0.keyCode == spec.keyCode }
            result.append(HotkeyBinding(action: action, keyCode: spec.keyCode, flags: flags))
        }
        return result
    }

    /// All active combos for an action (aliases included), sorted by key code.
    public static func activeCombos(_ defaultBindings: [HotkeyBinding], action: String) -> [String] {
        defaultBindings
            .filter { $0.action == action }
            .sorted { $0.keyCode < $1.keyCode }
            .map(\.display)
    }

    private static let flagOrder: [String] = ["cmd", "opt", "shift", "ctrl", "fn", "caps"]

    /// Canonical flag-name order for storage: `["cmd","opt","shift","ctrl","fn","caps"]`.
    public static func normalizedFlags(_ flags: [String]) -> [String] {
        var set: Set<String> = []
        for flag in flags {
            switch flag.lowercased() {
            case "cmd", "command": set.insert("cmd")
            case "opt", "alt", "option": set.insert("opt")
            case "shift": set.insert("shift")
            case "ctrl", "control": set.insert("ctrl")
            case "fn": set.insert("fn")
            case "caps", "capslock": set.insert("caps")
            default: continue
            }
        }
        return flagOrder.filter { set.contains($0) }
    }
}

extension HotkeyBindings {
    /// Symbols for a set of flag names, in display order (command, option,
    /// shift, control, fn, caps — matches the README's ⌘⌥[).
    public static func symbols(for flags: [String]) -> String {
        let table: [String: String] = [
            "ctrl": "⌃", "opt": "⌥", "shift": "⇧",
            "cmd": "⌘", "fn": "fn", "caps": "⇪",
        ]
        let order = ["cmd", "opt", "shift", "ctrl", "fn", "caps"]
        var used: Set<String> = []
        var out = ""
        for name in order {
            guard flags.contains(name), !used.contains(name) else { continue }
            used.insert(name)
            out += table[name] ?? ""
        }
        return out
    }

    /// Glyph for a US-layout virtual key code; falls back to "Key 0xNN".
    public static func keySymbol(for keyCode: UInt16) -> String {
        // US ANSI layout.
        let letters: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`",
        ]
        let extras: [UInt16: String] = [
            36: "⏎", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 122: "F1",
            120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        if let symbol = letters[keyCode] ?? extras[keyCode] {
            return symbol
        }
        return String(format: "Key 0x%02X", keyCode)
    }
}