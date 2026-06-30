import AppKit
import TesseraKit
import TesseraSystem

struct Tiler {
    let config: TesseraConfig

    /// Returns the workspace + mapper state for subsequent focus/remove operations.
    @discardableResult
    func tileAllWindows() -> (workspace: Workspace, mapper: WindowMapper)? {
        let allWindows = WindowDiscovery.allWindows()
        let windows = filterWindows(allWindows)

        print("[tiler] discovered \(allWindows.count) windows (\(windows.count) non-minimized + filtered)")
        for w in allWindows {
            let note = w.isMinimized ? " (minimized)" : ""
            print("[tiler]   \(w.appName): \"\(w.title)\" @ \(Int(w.position.x)),\(Int(w.position.y)) \(Int(w.size.width))x\(Int(w.size.height))\(note)")
        }

        guard !windows.isEmpty else {
            print("[tiler] no windows to tile — skipping")
            return nil
        }

        let screenRect = screenRect()
        print("[tiler] screen rect: \(screenRect)")

        var mapper = WindowMapper(realWindows: windows)
        print("[tiler] mapped \(mapper.pureWindows.count) pure windows")

        let workspace = Workspace(monitorRect: screenRect, config: config)

        for window in mapper.pureWindows {
            workspace.addWindow(window)
        }

        let layout = workspace.getLayout()
        print("[tiler] layout has \(layout.count) entries:")
        for (win, rect) in layout {
            print("[tiler]   \(win.id) → \(rect)")
        }

        mapper.applyLayout(layout)
        print("[tiler] layout applied ✓")
        return (workspace, mapper)
    }

    func filterWindows(_ allWindows: [MacWindow]) -> [MacWindow] {
        let screenFrame = screenCGRect()
        return allWindows.filter { w in
            guard !w.isMinimized else { return false }
            if w.title.isEmpty && w.position == .zero && w.size == screenFrame.size { return false }
            return true
        }
    }

    func screenCGRect() -> CGRect {
        NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private func screenRect() -> Rect {
        guard let screen = NSScreen.main else {
            return Rect(x: 0, y: 0, width: 1920, height: 1080)
        }
        let frame = screen.frame
        let visible = screen.visibleFrame
        // The visible frame excludes the menu bar and dock.
        // Convert from NSScreen's bottom-left to top-left coordinates
        // so the BSP engine matches AX's coordinate system.
        let topInset = frame.height - (visible.origin.y + visible.height)
        return Rect(
            x: Double(visible.origin.x),
            y: Double(topInset),
            width: Double(visible.size.width),
            height: Double(visible.size.height)
        )
    }
}
