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

> ⚠️ **Requirements**: The Swift daemon needs macOS **Accessibility** and **Input Monitoring** permissions. On macOS 15+ (this is "26"), TCC *only* honors those grants for processes born under a **granted GUI app** — a launchd child (LaunchAgent/LaunchDaemon/Login item) is **always denied**, no matter which entries you add in System Settings. Local/ad-hoc signed binaries also can't satisfy it (they carry no Apple-issued `TeamIdentifier`).
>
> So: grant your **terminal**, and let the daemon ride that terminal's lineage:
> ```
> System Settings → Privacy & Security → Accessibility → add Terminal.app (and your terminal)
> System Settings → Privacy & Security → Input Monitoring → add Terminal.app (and your terminal)
> ```
> Running `swift run TesseraDaemon` from your terminal — or `scripts/auth_start.zsh` (spawns it backgrounded via `nohup`, guarded by the PID file) — produces a daemon that can actually tile windows.

**Auto-start on login (installed by `scripts/install_menu.sh` / `tessera-install`)**

The menu bar app is bundled as `Tessera.app` (`com.spidey.tessera`) and launched at login by the `com.tessera.menu` LaunchAgent via `/usr/bin/open` (LaunchServices, so it runs as a proper GUI app). The *tiling daemon* is started separately by the `com.tessera.tiling` LaunchAgent, which opens **Terminal** once (`/usr/bin/open -a Terminal <app support>/auth_start.zsh`): the daemon is born as a descendant of the granted `Terminal.app` and therefore gets real Accessibility + Input Monitoring. A Terminal window briefly appears at login. The menu's **Start at Login** toggle installs/removes *both* agents together (the script is bundled in the app, so it works independently of the repo location). All wiring lives in one shared script, `scripts/tessera-install.sh` (used both by the repo and by Homebrew).

```bash
# Install: build Tessera.app, write both LaunchAgent plists, load them
./scripts/install_menu.sh

# Verify the running install (daemon, menu, both agents, grants)
./scripts/tessera-install.sh --check

# Remove: unload both agents, stop daemon/menu, delete app + logs
# (keeps ~/.config/tessera unless you pass --purge)
./scripts/uninstall.sh
# ./scripts/uninstall.sh --purge   # also remove your config
```

Notes:
- The daemon quit hotkey is honored (no `KeepAlive` relaunch). Restart it any time with:
  ```bash
  open -a Terminal "$HOME/Projects/tessera/scripts/auth_start.zsh"
  ```
- Logs go to `~/Library/Logs/Tessera/daemon.log` (stderr → `daemon.err.log`); menu/tiling agent output to `~/Library/Application Support/Tessera/menu.log` / `tiling.log`.
- Grants are tied to your terminal app and survive reinstall (the daemon install path can change).

**Menu bar companion (default)**

A menu bar status item that shows whether the daemon is running and can drive it without the terminal: tile now, reload config, open the config file / log folder, start/stop the daemon, and toggle start-at-login. `Settings…` (`⌘,`) edits the common `config.json` keys (gaps, animation, focus, per-app tiling rules) and live-reloads the running daemon — keys the UI doesn't edit (hotkeys, `excludedSubroles`, `multiMonitor`) are preserved on save.

- The menu app communicates with the daemon via a DistributedNotificationCenter channel (`TesseraDaemonCommand`) plus a PID file; no elevated permissions needed.
- The status dot turns green when the daemon is running (gray when stopped).
- The menu auto-starts a daemon *only* when the menu itself runs under a granted parent (e.g. launched from a permissioned Terminal); otherwise the `com.tessera.tiling` agent handles it at login.

**Homebrew (recommended for developers)**

```bash
# Tap this repository as a formula tap, then install
brew tap Spidey03/tessera https://github.com/Spidey03/tessera
brew install Spidey03/tessera/tessera
```

The formula builds a release `Tessera.app` (menu bar app + daemon + launcher) and installs three commands:

- `tessera` — the tiling daemon binary (`tessera --version`)
- `tessera-install` — wires up the login items (LaunchAgents) + prints the one-time grant steps
- `tessera-uninstall` — removes everything (keeps `~/.config/tessera` unless `--purge`)

After installing, run:

```bash
tessera-install            # login items + grant instructions
tessera-install --check    # verify daemon, menu, agents, grants
```

> ⚠️ **Do NOT use `brew services start tessera`.** macOS 15+ refuses
> Accessibility/Input Monitoring to launchd-spawned processes, so the daemon
> must be launched through a granted terminal (which `tessera-install` sets up).
>
> The first time, grant your terminal under
> System Settings → Privacy & Security → **Accessibility** and **Input Monitoring**.
> The daemon inherits those grants; a Terminal window briefly opens at login.

**Building the formula from a local checkout** (contributors, no GitHub release needed):

```bash
git archive --format=tar.gz -o /tmp/tessera-0.4.0.tar.gz HEAD
# Create /tmp/Tessera.rb from Formula/tessera.rb, pointing `url` at
# file:///tmp/tessera-0.4.0.tar.gz and setting `sha256 "$(shasum -a 256 /tmp/tessera-0.4.0.tar.gz)"`.
brew install --build-from-source /tmp/Tessera.rb
```

**Release ritual** (when cutting a new version):

1. Bump `version` in `TesseraKit/Sources/TesseraDaemon/main.swift`, `scripts/build_app.sh`, and `Formula/tessera.rb`; commit and push.
2. Tag and push: `git tag v0.4.1 && git push origin v0.4.1`
3. Upload the archive as an immutable **release asset** and pin the formula to it
   (tag-recreated tarballs are served stale by GitHub's cache, so releases use
   asset URLs — deterministic and byte-verified):
   ```bash
   git archive --format=tar.gz -o /tmp/tessera-v$VERSION.tar.gz HEAD
   gh release create v$VERSION /tmp/tessera-v$VERSION.tar.gz --title "Tessera v$VERSION"
   curl -Ls https://github.com/Spidey03/tessera/releases/download/v$VERSION/tessera-v$VERSION.tar.gz | shasum -a 256
   ```
4. Set that `sha256` in `Formula/tessera.rb` (keep the release-asset `url`), commit, push.
5. Reinstall via the tap to confirm the released artifact builds and runs.

### Hotkeys

| Shortcut | Action |
|----------|--------|
| `⌘⌥⏎` | Tile all windows |
| `⌘⌥H` / `⌘⌥K` | Focus left / previous |
| `⌘⌥J` / `⌘⌥L` | Focus right / next |
| `⌘⌥W` | Remove focused window |
| `⌘⌥F` | Toggle fullscreen |
| `⌘⌥Space` | Toggle split direction (bsp mode) |
| `⌘⌥.` | Cycle layout: bsp → master-stack → columns |
| `⌘⌥⇧Q` | Quit daemon |

### Layout Behavior

- **Layout presets** (`layoutMode` in `~/.config/tessera/config.json`, default `bsp`):
  - **bsp** — binary space partition tree (default, split-direction toggle per node)
  - **masterStack** — first window as a fixed-ratio master pane, the rest stacked as rows in the remaining column
  - **columns** — all windows as equal-width columns
  Cycle live with `⌘⌥.`, the menu's **Cycle Layout** item, or IPC `cycleLayout` / `setLayout:masterStack`. The runtime mode resets to the config value on reload/restart.
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
│       ├── TesseraTests/       # 77 Swift tests
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
