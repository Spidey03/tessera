import AppKit
import ApplicationServices
import CoreGraphics
import TesseraKit
import TesseraSystem

public struct WindowMapper {
    private var mapping: [String: MacWindow] = [:]

    public init(realWindows: [MacWindow]) {
        for win in realWindows {
            mapping[win.id] = win
        }
    }

    public func focusWindow(id: String) -> Bool {
        guard let macWin = mapping[id] else { return false }
        let appElement = AXUIElementCreateApplication(macWin.appPID)
        // Set the focused window on the app element (window-level kAXFocusedAttribute is read-only)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, macWin.windowRef)
        // Activate the app to bring it forward
        NSRunningApplication(processIdentifier: macWin.appPID)?.activate()
        print("[focus] set focused window: \(macWin.appName) \"\(macWin.title)\"")
        return true
    }

    public var focusedWindow: MacWindow? {
        mapping.values.first { $0.isGloballyFocused }
    }

    public var pureWindows: [Window] {
        // Sort by position (top-to-bottom, left-to-right) so the BSP tree
        // layout is deterministic and stable across consecutive tiles.
        mapping.values
            .sorted { a, b in
                if a.position.y != b.position.y { return a.position.y < b.position.y }
                if a.position.x != b.position.x { return a.position.x < b.position.x }
                return (a.appName, a.title) < (b.appName, b.title)
            }
            .map { Window(id: $0.id) }
    }

    public mutating func applyLayout(_ layout: [(Window, Rect)]) {
        var moved = 0, failed = 0
        for (pureWin, rect) in layout {
            guard var macWin = mapping[pureWin.id] else {
                print("[mapper]   SKIP: \(pureWin.id) not found in mapping")
                continue
            }
            let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            print("[mapper]   \(macWin.appName): \"\(macWin.title)\" → pos(\(Int(rect.x)),\(Int(rect.y))) size(\(Int(rect.width))x\(Int(rect.height)))")
            let posOK = macWin.setPosition(cgRect.origin)
            let szOK  = macWin.setSize(cgRect.size)
            if posOK && szOK {
                mapping[pureWin.id] = macWin
                moved += 1
            } else {
                print("[mapper]   FAILED: \(macWin.appName) — pos=\(posOK) size=\(szOK)")
                failed += 1
            }
        }
        print("[mapper] layout applied: \(moved) moved, \(failed) failed")
    }
}

extension MacWindow {
    var id: String {
        let ptr = Unmanaged<AXUIElement>.passUnretained(windowRef).toOpaque()
        return "\(ptr)"
    }
}
