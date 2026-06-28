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

    @discardableResult
    public mutating func setPosition(_ point: CGPoint) -> Bool {
        var val = point
        guard let axValue = AXValueCreate(.cgPoint, &val) else { return false }
        let result = AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute as CFString, axValue)
        guard result == .success else { return false }
        position = point
        return true
    }

    @discardableResult
    public mutating func setSize(_ newSize: CGSize) -> Bool {
        var val = newSize
        guard let axValue = AXValueCreate(.cgSize, &val) else { return false }
        let result = AXUIElementSetAttributeValue(windowRef, kAXSizeAttribute as CFString, axValue)
        guard result == .success else { return false }
        size = newSize
        return true
    }

    @discardableResult
    public mutating func setFrame(_ frame: CGRect) -> Bool {
        setPosition(frame.origin) && setSize(frame.size)
    }
}

extension MacWindow: CustomStringConvertible {
    public var description: String {
        let focusMark = isGloballyFocused ? " [global]" : isFocused ? " [app-focused]" : ""
        return "\(appName)[\(appPID)] \"\(title)\" at (\(Int(position.x)), \(Int(position.y))) \(Int(size.width))x\(Int(size.height))\(focusMark)"
    }
}
