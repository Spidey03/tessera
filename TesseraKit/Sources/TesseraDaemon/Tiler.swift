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
    /// Every window excluded from the BSP tree (config floaters + overflow
    /// floaters) — used to persist their absolute frames for restore on boot.
    let floatedIDs: Set<String>
    let animationTargets: [String: CGPoint]
}

struct Tiler {
    let config: TesseraConfig

    /// Per-display layout overrides. Displays without an override use
    /// `config.layoutMode`. Loaded from `state.json` at boot and persisted on
    /// change (see `Daemon.persistLayoutState`).
    var layoutState: LayoutState

    init(config: TesseraConfig, layoutState: LayoutState = LayoutState()) {
        self.config = config
        self.layoutState = layoutState
    }

    /// Effective layout mode for a display: override, else the config default.
    func layoutMode(for displayID: CGDirectDisplayID) -> LayoutMode {
        layoutState.mode(for: displayID, fallback: config.layoutMode)
    }

    /// Tiles every display's windows into its own BSP workspace.
    /// `previousOrderKeys` maps each display to the previous layout's window
    /// keys (appName|title) in order, so existing windows keep their tile slots.
    /// `previousSplitStates` maps each display to `Workspace.captureSplitState()` from the
    /// tiled state, so split weights survive re-tiles (also re-populated from
    /// disk on boot).
    /// Returns a per-display result dictionary (empty when no windows).
    @discardableResult
    func tileAllWindows(previousOrderKeys: [CGDirectDisplayID: [String]] = [:],
                        previousSplitStates: [CGDirectDisplayID: [String: SplitState]] = [:]) -> [CGDirectDisplayID: DisplayTileResult] {
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

        var results: [CGDirectDisplayID: DisplayTileResult] = [:]
        for display in displays {
            guard let displayWindows = windowsByDisplay[display.id], !displayWindows.isEmpty else { continue }
            // Preserve previous tile slots: existing windows keep their prior order
            // (and therefore their leaf), brand-new windows sort to the tail.
            let orderedWindows = WindowOrdering.reorder(
                displayWindows,
                previousKeyOrder: previousOrderKeys[display.id] ?? [],
                matchingKey: { "\($0.appName)|\($0.title)" },
                sortNew: { a, b in
                    if a.position.y != b.position.y { return a.position.y < b.position.y }
                    if a.position.x != b.position.x { return a.position.x < b.position.x }
                    return (a.appName, a.title) < (b.appName, b.title)
                }
            )
            results[display.id] = tileDisplay(display, windows: orderedWindows,
                                              splitStates: previousSplitStates[display.id] ?? [:])
        }
        return results
    }

    private func tileDisplay(_ display: DisplayInfo, windows: [MacWindow], splitStates: [String: SplitState] = [:]) -> DisplayTileResult {
        let screenRect = display.rect
        print("[tiler] screen \(display.name) rect: \(screenRect) — \(windows.count) windows")

        // Separate ignore, float, and normal apps
        let appRules = config.appRules
        let ignoreIDs = Set(windows.filter {
            guard let bid = $0.bundleID else { return false }
            return appRules[bid] == .ignore
        }.map(\.id))
        let floaterIDs = Set(windows.filter {
            guard let bid = $0.bundleID else { return false }
            return appRules[bid] == .float
        }.map(\.id))

        let tiledIDs = Set(windows.map(\.id)).subtracting(ignoreIDs).subtracting(floaterIDs)
        // Desired slot order: `windows` already arrive in preserved leaf order.
        let orderedTiledIDs = windows.filter { tiledIDs.contains($0.id) }.map(\.id)

        var mapper = WindowMapper(realWindows: windows)
        print("[tiler] mapped \(mapper.pureWindows.count) pure windows (\(tiledIDs.count) tiled, \(ignoreIDs.count) ignored, \(floaterIDs.count) floated)")

        // Build the display tree with only tiled windows, using the active
        // layout mode (bsp, masterStack or columns).
        let workspace = makeWorkspace(displayID: display.id, ordered: orderedTiledIDs, screenRect: screenRect, splitStates: splitStates)

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
            let remainingOrdered = orderedTiledIDs.filter { !floated.contains($0) }
            guard !remainingOrdered.isEmpty else {
                print("[tiler]   all remaining windows overflowed — giving up")
                break
            }
            resultWorkspace = makeWorkspace(displayID: display.id, ordered: remainingOrdered, screenRect: screenRect)
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
            floatedIDs: floaterIDs.union(allFloated),
            animationTargets: finalTargets
        )
    }

    /// Fresh tree for `orderedIDs` under the display's effective layout mode.
    /// Windows keep their previous slots because order is preserved by the caller;
    /// surviving split ratios are re-applied from `ratios`.
    private func makeWorkspace(displayID: CGDirectDisplayID, ordered orderedTiledIDs: [String], screenRect: Rect, splitStates: [String: SplitState] = [:]) -> Workspace {
        let workspace = Workspace(monitorRect: screenRect, config: config)
        workspace.applyPreset(layoutMode(for: displayID), orderedIDs: orderedTiledIDs)
        workspace.applySplitState(splitStates)
        return workspace
    }

    func filterWindows(_ allWindows: [MacWindow]) -> [MacWindow] {
        let displays = ScreenManager.displays
        let excludedSubroles = Set(config.excludedSubroles)
        let appRules = config.appRules

        return allWindows.filter { w in
            guard !w.isMinimized else { return false }

            // Role/subrole/size classification (standard AXWindow, non-excluded subrole, non-zero size)
            guard WindowFilter.isTileable(role: w.role, subrole: w.subrole, size: w.size, excludedSubroles: excludedSubroles) else {
                if let sr = w.subrole, WindowFilter.isExcludedSubrole(sr, excluded: excludedSubroles) {
                    print("[tiler] excluding \(w.appName): \"\(w.title)\" — subrole=\(sr)")
                } else if w.size.width <= 0 || w.size.height <= 0 {
                    print("[tiler] excluding \(w.appName): \"\(w.title)\" — zero-size window")
                }
                return false
            }

            // Skip desktop wallpaper windows on any display: fullscreen, empty title, at display origin
            if ScreenManager.isDesktopWallpaper(title: w.title, position: w.position, size: w.size, in: displays) {
                return false
            }

            // Per-app tiling rule: ignore = never consider this window at all
            if let bid = w.bundleID, case .ignore = appRules[bid] ?? .normal {
                print("[tiler] excluding \(w.appName): \"\(w.title)\" — appRule=ignore")
                return false
            }

            // Per-app tiling rule: float = keep in window list but exclude from BSP
            if let bid = w.bundleID, case .float = appRules[bid] ?? .normal {
                print("[tiler] marking \(w.appName): \"\(w.title)\" — appRule=float (will skip BSP)")
            }

            // Per-app tiling rule: sticky = tiled but slot never re-ranked
            if let bid = w.bundleID, case .sticky = appRules[bid] ?? .normal {
                print("[tiler] marking \(w.appName): \"\(w.title)\" — appRule=sticky (slot preserved)")
            }

            return true
        }
    }
}
