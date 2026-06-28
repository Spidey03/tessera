import AppKit
import ApplicationServices
import Foundation

public struct WindowDiscovery {

    public static func allWindows() -> [MacWindow] {
        let apps = runningApps()
        return apps.flatMap { windows(of: $0) }
    }

    public static func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    public static func windows(of app: NSRunningApplication) -> [MacWindow] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windowList: [AXUIElement] = getAttr(element: appElement, key: kAXWindowsAttribute) else {
            return []
        }

        return windowList.compactMap { win in
            let title: String = getAttr(element: win, key: kAXTitleAttribute) ?? ""
            let focused: Bool = getAttr(element: win, key: kAXFocusedAttribute) ?? false
            let minimized: Bool = getAttr(element: win, key: kAXMinimizedAttribute) ?? true

            guard let position = getPosition(element: win),
                  let size = getSize(element: win) else {
                return nil
            }

            return MacWindow(
                windowRef: win,
                appPID: app.processIdentifier,
                appName: app.localizedName ?? "(unknown)",
                title: title,
                position: position,
                size: size,
                isFocused: focused,
                isMinimized: minimized
            )
        }
        .filter { !$0.isMinimized }
    }

    // MARK: - AX attribute helpers

    private static func getAttr<T>(element: AXUIElement, key: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let val = value else { return nil }
        return val as? T
    }

    private static func getPosition(element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
        guard result == .success, let val = value else { return nil }
        let axVal = val as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axVal, .cgPoint, &point) else { return nil }
        return point
    }

    private static func getSize(element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
        guard result == .success, let val = value else { return nil }
        let axVal = val as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axVal, .cgSize, &size) else { return nil }
        return size
    }
}
