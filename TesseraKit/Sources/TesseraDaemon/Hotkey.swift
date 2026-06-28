import CoreGraphics
import Foundation

struct KeyBinding {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let action: String

    func matches(event: CGEvent) -> Bool {
        let eventKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard eventKeyCode == keyCode else { return false }
        // Only check that required flags are present; the system may set
        // additional device-specific flags that we shouldn't reject.
        return flags.isSubset(of: event.flags)
    }
}

extension KeyBinding {
    static let tile = KeyBinding(
        keyCode: 36, // Return
        flags: [.maskCommand, .maskAlternate],
        action: "tile"
    )
    static let quit = KeyBinding(
        keyCode: 12, // Q
        flags: [.maskCommand, .maskAlternate, .maskShift],
        action: "quit"
    )
    static let focusLeft = KeyBinding(
        keyCode: 4, // H
        flags: [.maskCommand, .maskAlternate],
        action: "focusLeft"
    )
    static let focusRight = KeyBinding(
        keyCode: 37, // L
        flags: [.maskCommand, .maskAlternate],
        action: "focusRight"
    )
    static let focusUp = KeyBinding(
        keyCode: 40, // K — vim up, aliased to focus left/previous
        flags: [.maskCommand, .maskAlternate],
        action: "focusLeft"
    )
    static let focusDown = KeyBinding(
        keyCode: 38, // J — vim down, aliased to focus right/next
        flags: [.maskCommand, .maskAlternate],
        action: "focusRight"
    )
    static let remove = KeyBinding(
        keyCode: 13, // W
        flags: [.maskCommand, .maskAlternate],
        action: "remove"
    )
}
