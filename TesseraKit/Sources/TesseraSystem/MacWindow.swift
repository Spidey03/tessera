import ApplicationServices
import Foundation

public struct MacWindow {
    public let windowRef: AXUIElement
    public let appPID: pid_t
    public let appName: String
    public let title: String
    public var position: CGPoint
    public var size: CGSize
    public let isFocused: Bool
    public let isGloballyFocused: Bool
    public let isMinimized: Bool

    public var frame: CGRect {
        CGRect(origin: position, size: size)
    }
}

extension MacWindow: CustomStringConvertible {
    public var description: String {
        let focusMark = isGloballyFocused ? " [global]" : isFocused ? " [app-focused]" : ""
        return "\(appName)[\(appPID)] \"\(title)\" at (\(Int(position.x)), \(Int(position.y))) \(Int(size.width))x\(Int(size.height))\(focusMark)"
    }
}
