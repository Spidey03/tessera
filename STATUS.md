# Tessera — Status

## What's Done

### Core Engine (TesseraKit)
- **BSP tree** with `addWindow` (splits largest leaf), `removeWindow` (collapses parent), `getLayout` (in-order leaves)
- **Geometry-based split direction**: split the longer dimension of the target leaf (wider → vertical, taller → horizontal). Removed global V/H alternation.
- **Split direction toggle** (`⌘⌥Space`): flips the focused window's parent split and reflows its subtree.
- **Split weight resize** (`⌘⌥[` / `⌘⌥]`): nudges the focused bsp split's ratio (positive = grows the focused window) within `splitMinRatio`…`splitMaxRatio`; step `splitResizeStep`. Ratios survive window add/remove and split toggles; reset on a full re-tile.
- **Layout presets** (`layoutMode`: `bsp` | `masterStack` | `columns`): master-stack gives the first window a `masterRatio` pane with the rest as rows; columns are equal-width. Modes are **independent per display** — `⌘⌥.` / menu **Cycle Layout** / IPC `cycleLayout` / `setLayout:<mode>` act on the focused display only — and each display's override persists to `~/.config/tessera/state.json` across restarts and reloads (pruned when a monitor unplugs).
- **Gap system**: `gapSize/2` inset from each tile edge, `outerGap` inset from screen edges, configurable via config file
- **Spatial focus navigation**: `focusLeft/Right/Up/Down` pick the nearest window in that direction (by proximity + overlap); `cycleNext/Prev` for tab-order cycling; `focusedWindowID` tracks the focused leaf
- **Largest-leaf strategy**: `findLargestLeaf()` replaces `findFocusedLeaf()` for balanced BSP tree; ties go to left child

### macOS Layer (TesseraSystem)
- **MacWindow**: AXUIElement wrapper with `setPosition`, `setSize`, `setPosition`, `actualSize`, `role`/`subrole`, `bundleID`
- **WindowDiscovery**: enumerates running apps and their windows via AX
- **WindowObserver**: subscribes to `kAXWindowCreatedNotification` per app; debounced callback triggers auto-tile; drag-triggered re-tile on move/resize (0.25s drag debounce); AX destroy notification replaces old polling
- **Config loader** (`ConfigLoader.swift`): reads `~/.config/tessera/config.json` (gapSize, outerGap, layoutMode, masterRatio, newWindowFocus, animation, multiMonitor, appRules, hotkey overrides); writes example config on first run; malformed file falls back to defaults
- **ScreenManager**: per-display rect conversion (NSScreen bottom-left → AX top-left coords), window/point-to-display lookup, desktop-wallpaper detection (incl. windows spanning multiple displays)

### Daemon
- **CGEventTap** captures keyDown events; matched bindings dispatched via `CFRunLoopPerformBlock`
- **Per-display BSP workspaces**: each display gets its own stateful `Workspace` + `WindowMapper`; windows are grouped to their containing display and tiled there
- **WindowMapper**: bridges pure `Window` ↔ `MacWindow`; `applyLayout`/`computeLayout` apply BSP rects and detect overflow; sorts by (y, x, appName, title) for deterministic BSP
- **Vim-style hotkeys**: H/I = focus left, J/M = focus right, K = up/prev, L = down/next; arrows cycle; remove (⌘⌥W); fullscreen (⌘⌥F); toggle split (⌘⌥Space); resize split (⌘⌥[ / ⌘⌥]); cycle layout on focused display (⌘⌥.); quit (⌘⌥⇧Q)
- **Coordinate fix**: per-display rect conversion in top-left coordinates matching AX — eliminates menu-bar induced overlap in horizontal splits
- **`floatingApps` config** (`floatingAppIDs: [String]`): floating apps stay out of the BSP tree and are screen-centered; legacy key auto-migrated into `appRules` as `.float`
- **Per-app tiling rules** (`appRules` config, `AppTilingRule`): `normal` (tiled), `float` (out of BSP, keeps position), `ignore` (completely untouched/invisible to tiler), `sticky` (tiled but keeps its tile slot across re-tiles via order-preserving rebuild)
- **Auto-float**: windows whose actual size overflows their tile by >50px are automatically screen-centered (catches minimum-size windows); floated windows removed from BSP and remaining windows re-tiled (cascade, ≤3 iterations)
- **AX role/subrole filtering**: `Tiler.filterWindows` keeps only `AXWindow` role and excludes non-standard subroles (dialog, sheet, floating, status, help, popover); the excluded set is config-overridable via `excludedSubroles` in `config.json`; zero-size windows are skipped
- **Animations**: easeOutQuad slide animation with configurable steps/duration; skip no-op auto-tiles via tileable-window fingerprints
- **Fullscreen toggle** (`⌘⌥F`): resizes focused window to fill its display; exiting restores its tile position

### Menu bar companion (TesseraMenu)
- **DistributedNotificationCenter IPC**: daemon listens on `TesseraDaemonCommand` (tile, focus*, remove, fullscreen, toggleSplit, reload, quit); posts `TesseraDaemonDidStart`/`DidQuit` and writes a PID file so the menu app detects liveness even if it launched after the daemon
- **Centralized dispatch**: hotkeys and IPC commands both funnel through `Daemon.handleAction(_:)`; `Daemon.reloadConfig()` swaps tiler/config/bindings live then re-tiles
- **NSStatusItem app** (`TesseraMenu`): SF-Symbol tile icon, green (running) / gray (stopped) dot, "Start at Login" toggle managing the `com.tessera.menu` and `com.tessera.tiling` LaunchAgents together; start/stop daemon, tile now, reload config, open config file / logs folder
- **App bundle**: menu packaged as `Tessera.app` (`com.spidey.tessera`, LSUIElement), launched at login via `/usr/bin/open` so it runs as a real LaunchServices GUI app
- **Granted-lineage startup (macOS 26)**: TCC denies Accessibility/Input Monitoring to launchd descendants and to any locally/ad-hoc signed binary (no Apple `TeamIdentifier`). The `com.tessera.tiling` LaunchAgent opens Terminal once (`/usr/bin/open -a Terminal <app support>/auth_start.zsh`) — the daemon spawns as a descendant of the *granted* Terminal, giving real event taps + tiling at login. Grants belong to your terminal app, not "Tessera". The menu auto-starts a daemon only when it itself runs under a granted parent.
- **Settings window** (`⌘,` or menu): edits `config.json` gaps, animation steps/duration, new-window-focus and per-app tiling rules; merges into the existing file (hotkeys, `excludedSubroles`, `multiMonitor` are preserved) and live-reloads the daemon over IPC
- **Graceful shutdown**: SIGTERM (launchctl stop) handler posts `DidQuit` and removes the PID file

### Testing
- 77 Swift tests (TesseraTests): BSP tree ops, spatial focus, split toggle, layout presets, keybinding matching, ScreenManager rect/wallpaper logic, slot-preserving order, subrole filtering
- 27 Python prototype tests (`tests/test_workspace.py`)

## What's Left

### Phase 3 — Customization / daily-driver
- [x] Per-monitor BSP workspaces
- [x] Split direction toggle (`⌘⌥Space`)
- [x] Per-app tiling rules (normal, ignore, float, sticky)
- [x] `sticky` app rule (window keeps its tile slot across re-tiles)
- [x] launchd agent integration (auto-start on login) — menu via `com.tessera.menu`; tiling daemon via granted-termininal lineage (`com.tessera.tiling` → `auth_start.zsh`)
- [x] Window role/subrole filtering refinements (config-overridable `excludedSubroles`)

### Phase 4 — Polish & packaging
- [x] Homebrew formula (tag-based `v0.4.0`, MIT, verified via local `brew install --build-from-source`; installs `Tessera.app` + `tessera`/`tessera-install`/`tessera-uninstall`)
- [x] Shared install wiring: `scripts/tessera-install.sh` / `scripts/tessera-uninstall.sh` (used by both the repo scripts and the Homebrew formula) incl. `--check` health verification
- [x] Menu bar app (`TesseraMenu` — status dot, tile/reload/start-stop, start-at-login)
- [x] Configuration UI (in-app settings: gaps, animation, focus, per-app rules; saves `config.json` preserving unedited keys and live-reloads via IPC)
