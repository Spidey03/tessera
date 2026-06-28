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
}
