# Tessera

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Python 3.9+](https://img.shields.io/badge/python-3.9+-3776AB?logo=python)
![Swift 6.0+](https://img.shields.io/badge/swift-6.0+-F05138?logo=swift)
![macOS 14.0+](https://img.shields.io/badge/macOS-14.0+-000000?logo=apple)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/Spidey03/tessera/pulls)

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
git clone https://github.com/Spidey03/tessera.git
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

> ⚠️ **Requirements**: The Swift daemon requires macOS **Accessibility** and **Input Monitoring** permissions. Grant them at:
> ```
> System Settings → Privacy & Security → Accessibility → Add Terminal
> System Settings → Privacy & Security → Input Monitoring → Add Terminal
> ```

**Auto-start on login (LaunchAgent)**

To run Tessera as a login agent that starts automatically (and stays up as a background daemon), use:

```bash
# Install: build release, write the plist, and load the agent
./scripts/install_daemon.sh

# Remove: unload the agent, delete the plist and installed binary
./scripts/uninstall_daemon.sh
```

This installs the release binary to `~/Library/Application Support/Tessera/TesseraDaemon`, writes a LaunchAgent plist (`com.tessera.daemon`), and loads it with `launchctl` so it starts on every login.

Notes:
- `KeepAlive` is off so the `⌘⌥⇧Q` quit hotkey isn't overridden by an immediate relaunch. Restart it any time with:
  ```bash
  launchctl kickstart -k "gui/$(id -u)/com.tessera.daemon"
  ```
- Logs go to `~/Library/Logs/Tessera/daemon.log` (stderr → `daemon.err.log`).
- If Accessibility/Input Monitoring prompts appear after a reinstall (new binary path), grant them once.

**Menu bar companion (optional)**

A menu bar status item that shows whether the daemon is running and can drive it without the terminal: tile now, reload config, open the config file / log folder, start/stop the daemon, and toggle start-at-login. `Settings…` (`⌘,`) edits the common `config.json` keys (gaps, animation, focus, per-app tiling rules) and live-reloads the running daemon — keys the UI doesn't edit (hotkeys, `excludedSubroles`, `multiMonitor`) are preserved on save.

```bash
# Install: build release, write the plist, and load the agent
./scripts/install_menu.sh

# Remove: unload the agent, delete the plist and installed binary
./scripts/uninstall_menu.sh
```

- The menu app communicates with the daemon via a DistributedNotificationCenter channel (`TesseraDaemonCommand`) plus a PID file; no elevated permissions needed.
- The status dot turns green when the daemon is running (gray when stopped).
- `Start at Login` installs the `com.tessera.menu` agent (this menu app only — the daemon is managed separately by `install_daemon.sh`).

**Homebrew (recommended)**

```bash
# Tap the formula
brew tap Spidey03/tessera

# Build & install (requires a GitHub release tagged v0.4.0 — see Release Ritual below)
brew install Spidey03/tessera/tessera
```

To test locally without a GitHub release, build from a local formula:

```bash
git archive --format=tar.gz -o /tmp/tessera-0.4.0.tar.gz HEAD
# Edit Formula/tessera.rb to point at file:///tmp/tessera-0.4.0.tar.gz + fill sha256
brew install --build-from-source Spidey03/tessera/tessera
brew test Spidey03/tessera/tessera
```

**Release Ritual**

1. Tag a release and push:
   ```bash
   git tag v0.4.0 && git push origin v0.4.0
   ```
2. Fill the formula's `sha256`:
   ```bash
   curl -Ls https://github.com/Spidey03/tessera/archive/refs/tags/v0.4.0.tar.gz | shasum -a 256
   ```
3. Install:
   ```bash
   brew install Spidey03/tessera/tessera
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
├── scripts/                  # LaunchAgent install/uninstall (daemon + menu bar app)
├── TesseraKit/               # Swift production code
│   ├── Package.swift
│   └── Sources/
│       ├── TesseraKit/Core/    # Pure Swift BSP engine
│       ├── TesseraSystem/      # macOS AX layer
│       ├── TesseraDaemon/      # Orchestrator + event loop
│       ├── TesseraMenu/        # Menu bar status/control app
│       ├── TesseraTests/       # 67 Swift tests
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
- [x] Fullscreen toggle (`⌘⌥F`)

**Phase 3** — Multi-monitor, hotkey customization, per-app rules
- [x] Per-monitor BSP workspaces
- [x] Split direction toggle (`⌘⌥Space`)
- [x] Per-app tiling rules (float, ignore, sticky, normal) — sticky keeps its tile slot across re-tiles
- [x] launchd agent integration (`scripts/install_daemon.sh`)
- [x] Window role/subrole filtering refinements (config-overridable `excludedSubroles`)

**Phase 4** — Polish, packaging, community
- [x] Homebrew formula (`Formula/tessera.rb`, tag-based install)
- [x] Menu bar app (`TesseraMenu`, `scripts/install_menu.sh`)
- [x] Configuration UI (in-app settings window; saves `config.json` + live reload)

---

## Contributing

PRs are welcome. The project is small and the architecture is deliberately simple.

- Brain changes (BSP math) go in `TesseraKit/Core/` and `tessera/core/`.
- Body changes (macOS) go in `TesseraSystem/` or `TesseraDaemon/`.
- Test coverage must be maintained. Run `swift run TesseraTests` (Swift) and `pytest` (Python) before opening a PR.

For bugs or feature requests, open an issue at [github.com/Spidey03/tessera/issues](https://github.com/Spidey03/tessera/issues).

---

## License

MIT. See [LICENSE](LICENSE) for details.
