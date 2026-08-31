# Tessera — Status

## What's Done

### Core Engine (TesseraKit)
- **BSP tree** with `addWindow` (splits largest leaf), `removeWindow` (collapses parent), `getLayout` (in-order leaves)
- **Geometry-based split direction**: split the longer dimension of the target leaf (wider → vertical, taller → horizontal). Removed global V/H alternation.
- **Split direction toggle** (`⌘⌥Space`): flips the focused window's parent split and reflows its subtree.
- **Gap system**: `gapSize/2` inset from each tile edge, `outerGap` inset from screen edges, configurable via config file
- **Spatial focus navigation**: `focusLeft/Right/Up/Down` pick the nearest window in that direction (by proximity + overlap); `cycleNext/Prev` for tab-order cycling; `focusedWindowID` tracks the focused leaf
- **Largest-leaf strategy**: `findLargestLeaf()` replaces `findFocusedLeaf()` for balanced BSP tree; ties go to left child

### macOS Layer (TesseraSystem)
- **MacWindow**: AXUIElement wrapper with `setPosition`, `setSize`, `setPosition`, `actualSize`, `role`/`subrole`, `bundleID`
- **WindowDiscovery**: enumerates running apps and their windows via AX
- **WindowObserver**: subscribes to `kAXWindowCreatedNotification` per app; debounced callback triggers auto-tile; drag-triggered re-tile on move/resize (0.25s drag debounce); AX destroy notification replaces old polling
- **Config loader** (`ConfigLoader.swift`): reads `~/.config/tessera/config.json` (gapSize, outerGap, newWindowFocus, animation, multiMonitor, appRules, hotkey overrides); writes example config on first run; malformed file falls back to defaults
- **ScreenManager**: per-display rect conversion (NSScreen bottom-left → AX top-left coords), window/point-to-display lookup, desktop-wallpaper detection (incl. windows spanning multiple displays)

### Daemon
- **CGEventTap** captures keyDown events; matched bindings dispatched via `CFRunLoopPerformBlock`
- **Per-display BSP workspaces**: each display gets its own stateful `Workspace` + `WindowMapper`; windows are grouped to their containing display and tiled there
- **WindowMapper**: bridges pure `Window` ↔ `MacWindow`; `applyLayout`/`computeLayout` apply BSP rects and detect overflow; sorts by (y, x, appName, title) for deterministic BSP
- **Vim-style hotkeys**: H/I = focus left, J/M = focus right, K = up/prev, L = down/next; arrows cycle; remove (⌘⌥W); fullscreen (⌘⌥F); toggle split (⌘⌥Space); quit (⌘⌥⇧Q)
- **Coordinate fix**: per-display rect conversion in top-left coordinates matching AX — eliminates menu-bar induced overlap in horizontal splits
- **`floatingApps` config** (`floatingAppIDs: [String]`): floating apps stay out of the BSP tree and are screen-centered; legacy key auto-migrated into `appRules` as `.float`
- **Per-app tiling rules** (`appRules` config, `AppTilingRule`): `normal` (tiled), `float` (out of BSP, keeps position), `ignore` (completely untouched/invisible to tiler)
- **Auto-float**: windows whose actual size overflows their tile by >50px are automatically screen-centered (catches minimum-size windows); floated windows removed from BSP and remaining windows re-tiled (cascade, ≤3 iterations)
- **AX role/subrole filtering**: `Tiler.filterWindows` keeps only `AXWindow` role and excludes non-standard subroles (dialog, sheet, floating, status, help)
- **Animations**: easeOutQuad slide animation with configurable steps/duration; skip no-op auto-tiles via tileable-window fingerprints
- **Fullscreen toggle** (`⌘⌥F`): resizes focused window to fill its display; exiting restores its tile position

### Testing
- 48 Swift tests (TesseraTests): BSP tree ops, spatial focus, split toggle, keybinding matching, ScreenManager rect/wallpaper logic
- 27 Python prototype tests (`tests/test_workspace.py`)

## What's Left

### Phase 3 — Customization / daily-driver
- [x] Per-monitor BSP workspaces
- [x] Split direction toggle (`⌘⌥Space`)
- [x] Per-app tiling rules (normal, ignore, float) — `sticky` rule not yet implemented
- [ ] `sticky` app rule (window keeps its tile slot across re-tiles)
- [ ] launchd agent integration (auto-start on login)

### Phase 4 — Polish & packaging
- [ ] Homebrew formula
- [ ] Dock icon / menu bar app
- [ ] Configuration UI (optional)
