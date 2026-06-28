# Tessera

A custom tiling window manager for macOS using a Binary Space Partitioning (BSP) tree layout engine.

## Architecture

Tessera follows a **Brain vs Body** decoupling:

| Layer | Target | Description |
|-------|--------|-------------|
| Python prototype | `tessera/core/` | Rapid prototyping of BSP engine (Rect, TreeNode, Workspace, 27 tests) |
| **TesseraKit** | `TesseraKit/Sources/TesseraKit/Core/` | Pure Swift BSP engine (no macOS deps) — Rect, Window, SplitType, TreeNode, Workspace, TesseraConfig |
| **TesseraSystem** | `TesseraKit/Sources/TesseraSystem/` | macOS AX layer — MacWindow, WindowDiscovery, WindowObserver |
| **TesseraDaemon** | `TesseraKit/Sources/TesseraDaemon/` | Orchestrator — CGEventTap hotkeys, Tiler, WindowMapper |

## Prerequisites

- macOS 14.0+ (arm64)
- Swift 6.0+ (included with Xcode 16+ or Command Line Tools)
- **Accessibility** permission for the terminal/IDE running the daemon
- **Input Monitoring** permission for global keyboard shortcuts

## Setup

```bash
git clone <repo>
cd TesseraKit
```

Grant permissions when prompted:

```
System Settings → Privacy & Security → Accessibility → Add Terminal
System Settings → Privacy & Security → Input Monitoring → Add Terminal
```

## Usage

```bash
cd TesseraKit
swift run TesseraDaemon
```

### Hotkeys

| Shortcut | Action |
|----------|--------|
| `⌘⌥⏎` | Tile all windows |
| `⌘⌥H` / `⌘⌥K` | Focus left / previous |
| `⌘⌥J` / `⌘⌥L` | Focus right / next |
| `⌘⌥W` | Remove focused window |
| `⌘⌥⇧Q` | Quit daemon |

### Layout Behavior

- **Split direction** alternates: Vertical → Horizontal → Vertical → ...
- **New window** goes to the right (vertical split) or bottom (horizontal split)
- **Focus** stays on the existing window after a split (configurable)
- **Gaps**: 8px between windows, 4px outer margin (configurable)

## Project Status

### ✅ Completed

| Feature | Status |
|---------|--------|
| Python BSP prototype (Rect, TreeNode, Workspace, tests) | Done |
| Swift BSP engine (TesseraKit) with 16 tests | Done |
| AX window discovery (WindowDiscover CLI) | Done |
| Window move/resize via AX | Done |
| CGEventTap daemon (⌘⌥⏎ to tile, ⌘⌥⇧Q to quit) | Done |
| WindowObserver — auto-tile on window create | Done |
| WindowMapper — bridges pure Window ↔ MacWindow | Done |
| Focus navigation (⌘⌥H/J/K/L) | Done |
| Window removal (⌘⌥W) with re-tile | Done |

### 📋 Planned

- AX notifications for window destroy
- Config file (`~/.config/tessera/config.json`)
- Multi-monitor support
- Fullscreen toggle (⌘⌥F)
- Split direction toggle (⌘⌥Space)
- Per-app tiling rules
- launchd agent integration

## Development

### Run tests

```bash
cd TesseraKit
swift run TesseraTests
```

### Python tests (prototype)

```bash
source venv/bin/activate
pip install -e .
pytest tests/
```

### Debug discovery

```bash
cd TesseraKit
swift run WindowDiscover
```

## Files

```
TesseraKit/
├── Package.swift
└── Sources/
    ├── TesseraKit/
    │   └── Core/
    │       ├── Rect.swift          # Rectangle with split/gap helpers
    │       ├── Window.swift        # Pure window identity (id + rect)
    │       ├── SplitType.swift     # Vertical / Horizontal
    │       ├── TreeNode.swift      # BSP tree node
    │       ├── Workspace.swift     # BSP layout engine
    │       └── TesseraConfig.swift # Gap/split/focus config
    ├── TesseraSystem/
    │   ├── MacWindow.swift         # AXUIElement wrapper + move/resize
    │   ├── WindowDiscovery.swift   # Enumerate windows via AX
    │   └── WindowObserver.swift    # AX notification subscriber
    ├── TesseraDaemon/
    │   ├── main.swift              # Entry point
    │   ├── Daemon.swift            # CGEventTap + run loop
    │   ├── Tiler.swift             # Window discovery → BSP → layout
    │   ├── WindowMapper.swift      # Bridge pure Window ↔ MacWindow
    │   └── Hotkey.swift            # KeyBinding matching
    ├── TesseraTests/
    │   └── main.swift              # 16 BSP engine tests
    └── WindowDiscover/
        └── main.swift              # AX window enumeration CLI
```
