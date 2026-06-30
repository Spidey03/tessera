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

    @discardableResult
    public mutating func applyLayout(_ layout: [(Window, Rect)]) -> Set<String> {
        let tolerance: CGFloat = 8
        var moved = 0
        var floatedIDs: Set<String> = []
        for (pureWin, rect) in layout {
            guard var macWin = mapping[pureWin.id] else {
                print("[mapper]   SKIP: \(pureWin.id) not found in mapping")
                continue
            }
            let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)

            // Request resize — app may or may not honor it
            macWin.setSize(cgRect.size)

            // Read back what the app actually accepted
            let actual = macWin.actualSize()
            let dx = actual.map { abs($0.width - cgRect.width) } ?? 0
            let dy = actual.map { abs($0.height - cgRect.height) } ?? 0
            let fits = dx <= tolerance && dy <= tolerance

            let position: CGPoint
            if !fits {
                let actualW = actual?.width ?? cgRect.width
                let actualH = actual?.height ?? cgRect.height
                let dW = abs(actualW - cgRect.width)
                let dH = abs(actualH - cgRect.height)
                let isMismatch = dW > 50 || dH > 50

                if isMismatch {
                    floatedIDs.insert(pureWin.id)
                    position = screenCenter(size: CGSize(width: actualW, height: actualH))
                    print("[mapper]   \(macWin.appName): \"\(macWin.title)\" → auto-floated (mismatch \(Int(max(dW, dH)))px) at (\(Int(position.x)),\(Int(position.y)))")
                } else {
                    position = cgRect.origin
                    print("[mapper]   WARNING: \(macWin.appName) \"\(macWin.title)\" — requested \(Int(cgRect.width))x\(Int(cgRect.height)), got \(Int(actualW))x\(Int(actualH)); placing at tile position")
                }
            } else {
                position = cgRect.origin
                print("[mapper]   \(macWin.appName): \"\(macWin.title)\" → pos(\(Int(rect.x)),\(Int(rect.y))) size(\(Int(rect.width))x\(Int(rect.height)))")
            }

            if macWin.setPosition(position) {
                mapping[pureWin.id] = macWin
                moved += 1
            }
        }
        print("[mapper] layout applied: \(moved) moved")
        if !floatedIDs.isEmpty {
            print("[mapper] floated \(floatedIDs.count) window(s)")
        }
        return floatedIDs
    }

    @discardableResult
    public mutating func centerOnScreen(id: String) -> Bool {
        guard var macWin = mapping[id] else { return false }
        let actual = macWin.actualSize() ?? macWin.size
        let pos = screenCenter(size: actual)
        if macWin.setPosition(pos) {
            mapping[id] = macWin
            print("[mapper]   \(macWin.appName): \"\(macWin.title)\" → centered on screen at (\(Int(pos.x)),\(Int(pos.y)))")
            return true
        }
        return false
    }

    private func screenCenter(size: CGSize) -> CGPoint {
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 33, width: 1512, height: 944)
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let topInset = round(screenFrame.height - visibleFrame.origin.y - visibleFrame.height)
        let cx = visibleFrame.origin.x + (visibleFrame.width - size.width) / 2
        let cy = topInset + (visibleFrame.height - size.height) / 2
        return CGPoint(x: max(cx, 0), y: max(cy, topInset))
    }
}

extension MacWindow {
    var id: String {
        let ptr = Unmanaged<AXUIElement>.passUnretained(windowRef).toOpaque()
        return "\(ptr)"
    }
}
