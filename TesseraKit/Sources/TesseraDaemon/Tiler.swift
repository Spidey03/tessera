import AppKit
import TesseraKit
import TesseraSystem

/// Result of tiling one display's windows.
struct DisplayTileResult {
    let displayID: CGDirectDisplayID
    let screenRect: Rect
    let workspace: Workspace
    let mapper: WindowMapper
    let newlyFloated: Set<String>
    let animationTargets: [String: CGPoint]
}

struct Tiler {
    let config: TesseraConfig

    /// Tiles every display's windows into its own BSP workspace.
    /// Returns a per-display result dictionary (empty when no windows).
    @discardableResult
    func tileAllWindows() -> [CGDirectDisplayID: DisplayTileResult] {
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
            return [:]
        }

        let displays = ScreenManager.displays
        print("[tiler] displays: \(displays.map { "\($0.name)(\($0.id))" }.joined(separator: ", "))")

        // Group windows by containing display (window center decides)
        var windowsByDisplay: [CGDirectDisplayID: [MacWindow]] = [:]
        var unassigned: [MacWindow] = []
        for w in windows {
            if let display = ScreenManager.display(containing: w.frame, in: displays) {
                windowsByDisplay[display.id, default: []].append(w)
            } else {
                unassigned.append(w)
            }
        }
        // Off-screen / unknown windows fall back to the main display
        if !unassigned.isEmpty, let fallbackID = ScreenManager.mainDisplayID {
            windowsByDisplay[fallbackID, default: []].append(contentsOf: unassigned)
            print("[tiler] \(unassigned.count) window(s) not on any display — assigned to main (\(fallbackID))")
        }

        let configFloaterBundleIDs = Set(config.floatingAppIDs)
        var results: [CGDirectDisplayID: DisplayTileResult] = [:]
        for display in displays {
            guard let displayWindows = windowsByDisplay[display.id], !displayWindows.isEmpty else { continue }
            results[display.id] = tileDisplay(display, windows: displayWindows, configFloaterBundleIDs: configFloaterBundleIDs)
        }
        return results
    }

    private func tileDisplay(_ display: DisplayInfo, windows: [MacWindow], configFloaterBundleIDs: Set<String>) -> DisplayTileResult {
        let screenRect = display.rect
        print("[tiler] screen \(display.name) rect: \(screenRect) — \(windows.count) windows")

        // Separate config-floaters (never enter BSP tree) from tiled candidates
        let floaterIDs = Set(windows.filter { configFloaterBundleIDs.contains($0.bundleID ?? "") }.map(\.id))
        let tiledIDs = Set(windows.map(\.id)).subtracting(floaterIDs)

        var mapper = WindowMapper(realWindows: windows)
        print("[tiler] mapped \(mapper.pureWindows.count) pure windows (\(tiledIDs.count) tiled, \(floaterIDs.count) config-floated)")

        // Build BSP tree with only tiled windows
        let workspace = Workspace(monitorRect: screenRect, config: config)
        for window in mapper.pureWindows where tiledIDs.contains(window.id) {
            workspace.addWindow(window)
        }

        let layout = workspace.getLayout()
        print("[tiler]   layout has \(layout.count) entries:")
        for (win, rect) in layout {
            print("[tiler]     \(win.id) → \(rect)")
        }

        // Compute layout (resize for overflow detection but don't move windows)
        var (targets, floated) = mapper.computeLayout(layout, screenRect: screenRect)
        var allFloated = floated
        var finalTargets = targets

        // Cascade: if a tiled window overflowed, rebuild the tree without it
        var resultWorkspace = workspace
        var iteration = 0
        while !floated.isEmpty && iteration < 3 {
            iteration += 1
            let remaining = tiledIDs.subtracting(floated)
            guard !remaining.isEmpty else {
                print("[tiler]   all remaining windows overflowed — giving up")
                break
            }
            resultWorkspace = Workspace(monitorRect: screenRect, config: config)
            for id in remaining.sorted() {
                resultWorkspace.addWindow(Window(id: id))
            }
            let newLayout = resultWorkspace.getLayout()
            if newLayout.isEmpty { break }
            (targets, floated) = mapper.computeLayout(newLayout, screenRect: screenRect)
            finalTargets = targets
            allFloated.formUnion(floated)
        }

        let tiledCount = max(0, tiledIDs.count - allFloated.count)
        print("[tiler]   layout applied ✓ (\(tiledCount) tiled, \(allFloated.count) floated)")
        return DisplayTileResult(
            displayID: display.id,
            screenRect: screenRect,
            workspace: resultWorkspace,
            mapper: mapper,
            newlyFloated: allFloated,
            animationTargets: finalTargets
        )
    }

    func filterWindows(_ allWindows: [MacWindow]) -> [MacWindow] {
        let displays = ScreenManager.displays
        let excludedSubroles: Set<String> = [
            "AXDialog",
            "AXSheet",
            "AXFloatingWindow",
            "AXSystemFloatingWindow",
            "AXStatusWindow",
            "AXHelpWindow",
        ]
        return allWindows.filter { w in
            guard !w.isMinimized else { return false }
            guard w.role == "AXWindow" else { return false }
            // Skip desktop wallpaper windows on any display: fullscreen, empty title, at display origin
            if ScreenManager.isDesktopWallpaper(title: w.title, position: w.position, size: w.size, in: displays) {
                return false
            }
            // Exclude non-standard window types (dialogs, sheets, floating panels, etc.)
            if let sr = w.subrole, excludedSubroles.contains(sr) {
                print("[tiler] excluding \(w.appName): \"\(w.title)\" — subrole=\(sr)")
                return false
            }
            return true
        }
    }
}
