import ApplicationServices
import Foundation

public struct MacWindow {
    public let windowRef: AXUIElement
    public let appPID: pid_t
    public let appName: String
    public let bundleID: String?
    public let title: String
    public let role: String?
    public let subrole: String?
    public var position: CGPoint
    public var size: CGSize
    public let isFocused: Bool
    public let isGloballyFocused: Bool
    public let isMinimized: Bool
    /// `CGWindowID` of the window (via `_AXUIElementGetWindow`). Unique per window
    /// and independent of its title. Nil if the lookup failed.
    public var windowNumber: CGWindowID? = nil

    public init(windowRef: AXUIElement, appPID: pid_t, appName: String, bundleID: String?,
                title: String, role: String?, subrole: String?, position: CGPoint, size: CGSize,
                isFocused: Bool, isGloballyFocused: Bool, isMinimized: Bool,
                windowNumber: CGWindowID? = nil) {
        self.windowRef = windowRef
        self.appPID = appPID
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.role = role
        self.subrole = subrole
        self.position = position
        self.size = size
        self.isFocused = isFocused
        self.isGloballyFocused = isGloballyFocused
        self.isMinimized = isMinimized
        self.windowNumber = windowNumber
    }

    public var frame: CGRect {
        CGRect(origin: position, size: size)
    }

    /// Identity that survives a fresh discovery pass.
    ///
    /// NOT `id`: that is the `AXUIElement` pointer, and every
    /// `AXUIElementCopyWindows` call builds new CF objects, so the same window
    /// gets a different pointer on the next tile. Anything that compares
    /// windows *across* tiles (layout order preservation, float frames, tile
    /// trigger classification) must key on this instead.
    ///
    /// Collides for two same-titled windows in one app (two "Untitled"
    /// documents), which is the same tradeoff `Daemon.floaterKey` and the
    /// layout-order key already accept.
    public var stableID: String {
        "\(appName)|\(title)"
    }

    /// Identity for split-state keys within one daemon session. Uses the window
    /// number when available: it is title-independent (terminal and browser titles
    /// change constantly) and unique per window. Falls back to `stableID` only when
    /// the lookup failed, in which case duplicate titles are caught by the caller.
    public var splitIdentity: String {
        if let windowNumber { return "win:\(windowNumber)" }
        return stableID
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
        guard setSize(frame.size) else { return false }
        return setPosition(frame.origin)
    }

    public func actualSize() -> CGSize? {
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(windowRef, kAXSizeAttribute as CFString, &raw)
        guard result == .success, let val = raw else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(val as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}

extension MacWindow: CustomStringConvertible {
    public var description: String {
        let focusMark = isGloballyFocused ? " [global]" : isFocused ? " [app-focused]" : ""
        let subroleTag = subrole.map { " [\($0)]" } ?? ""
        return "\(appName)[\(appPID)] \"\(title)\" at (\(Int(position.x)), \(Int(position.y))) \(Int(size.width))x\(Int(size.height))\(subroleTag)\(focusMark)"
    }
}
