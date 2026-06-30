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
            let roleNote = (w.role ?? "?").hasPrefix("AX") ? "" : " [role=\(w.role ?? "nil")]"
            print("[tiler]   \(w.appName): \"\(w.title)\" @ \(Int(w.position.x)),\(Int(w.position.y)) \(Int(w.size.width))x\(Int(w.size.height))\(roleNote)\(note)")
        }

        guard !windows.isEmpty else {
            print("[tiler] no windows to tile — skipping")
            return nil
        }

        let screenRect = screenRect()
        print("[tiler] screen rect: \(screenRect)")

        // Separate config-floaters (never enter BSP tree) from tiled candidates
        let configFloaterBundleIDs = Set(config.floatingAppIDs)
        let floaterIDs = Set(windows.filter { configFloaterBundleIDs.contains($0.bundleID ?? "") }.map(\.id))
        let tiledIDs = Set(windows.map(\.id)).subtracting(floaterIDs)

        var mapper = WindowMapper(realWindows: windows)
        print("[tiler] mapped \(mapper.pureWindows.count) pure windows (\(tiledIDs.count) tiled, \(floaterIDs.count) floating)")

        // Build BSP tree with only tiled windows
        let workspace = Workspace(monitorRect: screenRect, config: config)
        for window in mapper.pureWindows where tiledIDs.contains(window.id) {
            workspace.addWindow(window)
        }

        let layout = workspace.getLayout()
        print("[tiler] layout has \(layout.count) entries:")
        for (win, rect) in layout {
            print("[tiler]   \(win.id) → \(rect)")
        }

        // Apply layout to tiled windows; misfits are auto-floated
        var floated = mapper.applyLayout(layout)

        // Screen-center config-floaters (they never entered the tree)
        for id in floaterIDs {
            mapper.centerOnScreen(id: id)
        }

        // Cascade: if a tiled window misfit, rebuild without it
        var resultWorkspace = workspace
        while !floated.isEmpty {
            print("[tiler] re-tiling without \(floated.count) floated window(s)")
            let remaining = tiledIDs.subtracting(floated)
            guard !remaining.isEmpty else {
                print("[tiler] all windows floated — nothing to tile")
                return nil
            }
            resultWorkspace = Workspace(monitorRect: screenRect, config: config)
            for id in remaining {
                resultWorkspace.addWindow(Window(id: id))
            }
            let newLayout = resultWorkspace.getLayout()
            if newLayout.isEmpty { break }
            floated = mapper.applyLayout(newLayout)
        }

        print("[tiler] layout applied ✓")
        return (resultWorkspace, mapper)
    }

    func filterWindows(_ allWindows: [MacWindow]) -> [MacWindow] {
        let screenFrame = screenCGRect()
        return allWindows.filter { w in
            guard !w.isMinimized else { return false }
            // Only tile real application windows (skip desktop widgets, helper panels, etc.)
            guard w.role == "AXWindow" else { return false }
            // Skip desktop wallpaper windows: fullscreen, empty title, at origin
            if w.title.isEmpty && w.position == .zero && w.size == screenFrame.size { return false }
            return true
        }
    }

    private func screenCGRect() -> CGRect {
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
