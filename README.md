# Tessera

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Python 3.12+](https://img.shields.io/badge/python-3.12+-3776AB?logo=python)
![Swift 6.0+](https://img.shields.io/badge/swift-6.0+-F05138?logo=swift)
![macOS 14.0+](https://img.shields.io/badge/macOS-14.0+-000000?logo=apple)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/anomalyco/tessera/pulls)

**Tessera** is a lightning-fast, animation-free tiling window manager for macOS powered by a Binary Space Partitioning (BSP) tree and virtual workspaces. It bypasses macOS's sluggish Space animations entirely — compute, hide, show, resize. Instantly.

---

## Why Tessera?

**Virtual Workspaces** — No slow macOS Space switching. All windows live on a single invisible canvas. Tessera instantly computes which windows to show, hide, and resize based on your active workspace. Zero animation, zero delay.

**Animation-Free** — macOS applies a 300-500ms animation every time you switch Spaces. Tessera doesn't switch Spaces. It hides and shows windows via the Accessibility API in a single frame.

**Keyboard-Driven Focus** — Navigate windows with vector math, not tab order. Focus left, right, up, or down relative to your current position in the BSP tree. Every movement is deterministic and instant.

**Pure Math at the Core** — The layout engine is an OS-agnostic BSP tree. Split, remove, and balance leaves with simple arithmetic. The same logic runs in the Python prototype and the production Swift build.

---

## Architecture: Brain vs Body

Tessera separates the "what" from the "how".

| Layer | Role | Description |
|-------|------|-------------|
| **Brain** | Layout Engine | Pure BSP tree math. Zero OS dependencies. Prototyped in Python, ported to Swift as `TesseraKit`. Calculates split positions, focus paths, and gap insets. |
| **Body** | macOS Bridge | Accessibility API (AXUIElement) calls. Enumerates windows, sets positions and sizes, subscribes to window-create notifications. Lives in `TesseraSystem` and `TesseraDaemon`. |

This split means the entire tiling algorithm can be unit-tested without a display server. The Body is a thin translation layer — convert pure `Rect` values to `CGRect`, hand them to AX, done.

```
┌─────────────────────────────────────────┐
│              Daemon (Swift)             │
│  ┌──────────┐    ┌───────────────────┐  │
│  │  Tiler   │───→│  WindowMapper     │  │
│  │          │    │  (pure → AX)      │  │
│  └──────────┘    └───────────────────┘  │
│  ┌───────┴----------------------------┐ │ 
│  │         Workspace (BSP)            │ │
│  │        Brain: no OS deps           │ │
│  └────────────────────────────---─────┘ │
└─────────────────────────────────────────┘
```

---

## Installation & Quick Start

**Phase 1 — Python Prototype**

```bash
git clone https://github.com/anomalyco/tessera.git
cd tessera

python3 -m venv venv
source venv/bin/activate
pip install -e .

# Run the BSP layout simulation
python3 -c "
from tessera.core.workspace import Workspace
from tessera.core.rect import Rect

ws = Workspace(Rect(0, 0, 1920, 1080))
ws.add_window('A')
ws.add_window('B')
ws.add_window('C')
for w, r in ws.get_layout():
    print(f'{w.id}: {r}')
"
```

**Phase 2+ — Swift Daemon (current)**

```bash
cd TesseraKit
swift run TesseraDaemon
```

> ⚠️ **Future Requirements**: The Swift daemon will require macOS **Accessibility** and **Input Monitoring** permissions. Grant them at:
> ```
> System Settings → Privacy & Security → Accessibility → Add Terminal
> System Settings → Privacy & Security → Input Monitoring → Add Terminal
> ```

### Hotkeys

| Shortcut | Action |
|----------|--------|
| `⌘⌥⏎` | Tile all windows |
| `⌘⌥H` / `⌘⌥K` | Focus left / previous |
| `⌘⌥J` / `⌘⌥L` | Focus right / next |
| `⌘⌥W` | Remove focused window |
| `⌘⌥⇧Q` | Quit daemon |

### Layout Behavior

- **Split direction** is geometry-based: split the longer dimension of the target leaf (wider → vertical, taller → horizontal).
- **New window** splits the largest leaf by area for balanced tile sizes.
- **Focus** stays on the existing window after a split (configurable via `~/.config/tessera/config.json`).
- **Gaps**: 8px between windows, 4px outer margin (configurable).

---

## Development

### Swift Tests

```bash
cd TesseraKit
swift run TesseraTests
```

### Python Tests (prototype)

```bash
source venv/bin/activate
pytest tests/
```

### Debug Window Discovery

```bash
cd TesseraKit
swift run WindowDiscover
```

---

## Project Structure

```
tessera/
├── tessera/                    # Python BSP prototype
│   └── core/
│       ├── rect.py
│       ├── window.py
│       ├── workspace.py
│       └── split_type.py
├── tests/                      # Python tests (27)
├── TesseraKit/                 # Swift production code
│   ├── Package.swift
│   └── Sources/
│       ├── TesseraKit/Core/    # Pure Swift BSP engine
│       ├── TesseraSystem/      # macOS AX layer
│       ├── TesseraDaemon/      # Orchestrator + event loop
│       ├── TesseraTests/       # 31 BSP engine tests
│       └── WindowDiscover/     # AX enumeration CLI
└── README.md
```

---

## Roadmap

**Phase 1** ✅ — Core BSP layout engine (Python prototype + Swift port)
- [x] Rect split/gap arithmetic
- [x] BSP tree (add, remove, find largest leaf)
- [x] Geometry-based split direction
- [x] Focus navigation by vector position

**Phase 2** 🚧 — macOS Accessibility hooks (current)
- [x] AX window discovery and enumeration
- [x] Window move/resize via AXUIElement
- [x] CGEventTap global hotkey daemon
- [x] WindowObserver for auto-tile on create
- [x] Config file support (`~/.config/tessera/config.json`)
- [x] Poll-based window destroy detection
- [ ] Fullscreen toggle (`⌘⌥F`)

**Phase 3** — Multi-monitor, hotkey customization, per-app rules
- [ ] Per-monitor BSP workspaces
- [ ] Split direction toggle (`⌘⌥Space`)
- [ ] Per-app tiling rules (float, ignore, sticky)
- [ ] launchd agent integration

**Phase 4** — Polish, packaging, community
- [ ] Homebrew formula
- [ ] Dock icon / menu bar app
- [ ] Configuration UI (optional)

---

## Contributing

PRs are welcome. The project is small and the architecture is deliberately simple.

- Brain changes (BSP math) go in `TesseraKit/Core/` and `tessera/core/`.
- Body changes (macOS) go in `TesseraSystem/` or `TesseraDaemon/`.
- Test coverage must be maintained. Run `swift run TesseraTests` (Swift) and `pytest` (Python) before opening a PR.

For bugs or feature requests, open an issue at [github.com/anomalyco/tessera/issues](https://github.com/anomalyco/tessera/issues).

---

## License

MIT. See [LICENSE](LICENSE) for details.
