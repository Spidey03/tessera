# Tessera User Guide

Tessera is a keyboard-driven tiling window manager for macOS. It arranges your
windows in a binary space-partitioning (BSP) tree on a virtual workspace — no
delays, no macOS Space animations.

Tessera runs as two pieces:

| Piece | What it is | Where it is |
|-------|-----------|-------------|
| **Menu bar app** (`TesseraMenu`) | The status-item control point. Shows a square-split icon in the menu bar and drives/controls the daemon: start/stop, reload config, settings, updates. | Menu bar icon (green dot = daemon running, gray = stopped) |
| **Tiling daemon** (`TesseraDaemon`) | The tiling engine. Enumerates your windows, tiles them, listens for hotkeys and window changes. | A background process |

Both start automatically at login (see below). You control everything from the
menu icon or the keyboard.

---

## Install

Choose one of these. The Homebrew formula is the recommended path; all three
produce the same result afterwards.

### Option A — Homebrew formula (recommended)

```bash
brew tap Spidey03/tessera
brew install Spidey03/tessera/tessera
```

This installs three commands:

- `tessera` — the daemon binary
- `tessera-install` — wires up the login items + prints the one-time grant steps
- `tessera-uninstall` — removes everything

Then wire up the login items once:

```bash
tessera-install
```

> ⚠️ **Do NOT run `brew services start tessera`.** On macOS 15+ the system
> denies Accessibility and Input Monitoring grants to launchd-spawned
> processes, so the daemon must be started through a granted terminal instead.
> `tessera-install` sets that up for you.

### Option B — Homebrew cask / DMG (unsigned builds)

```bash
brew install --cask Spidey03/tessera/tessera
```

This installs `Tessera.app` into `/Applications`. The current release is
unsigned/ad-hoc signed, so macOS Gatekeeper blocks the first launch — right-click
the app once and choose **Open**. (A signed, notarized build that skips this
step is a declared next release.)

Then wire up the login items:

```bash
tessera-install --app /Applications/Tessera.app
```

### Option C — From source (developers)

```bash
git clone https://github.com/Spidey03/tessera.git
cd tessera
./scripts/install_menu.sh
```

This builds the app and wires up everything for you. The repo also exposes the
shared scripts directly (`scripts/tessera-install.sh`, `scripts/tessera-uninstall.sh`).

### One-time permissions (all install methods)

macOS requires two privacy grants for tiling to work:

```
System Settings → Privacy & Security → Accessibility
System Settings → Privacy & Security → Input Monitoring
```

- **Unsigned / ad-hoc build (current):** macOS only honors these grants for an
  app that carries Apple's TeamIdentifier. Tessera isn't signed yet, so you
  grant your **terminal** (Terminal.app, kitty, iTerm, etc.). The daemon is
  launched *through* your terminal and inherits its grants — that's why a
  **Terminal window may appear briefly at login**. This is expected.
- **Developer-ID signed build (future):** you would grant **Tessera itself**
  (add the app in both panes) and login is fully silent — no Terminal popup.

The menu bar's **Grant Permissions** ▸ *Accessibility… / Input Monitoring…*
submenu opens these two panes for you at any time.

### Verify the install

```bash
tessera-install --check
```

It reports whether the daemon and menu bar app are running, both login agents
are loaded, and the Accessibility grant is detected.

---

## What "install" does to your system

So you know exactly what a install changes:

| Path | Purpose |
|------|---------|
| `~/Library/Application Support/Tessera/Tessera.app` | The installed app bundle (menu + daemon) |
| `~/Library/LaunchAgents/com.tessera.menu.plist` | Login agent: starts the menu bar app at login (`RunAtLoad`, no auto-relaunch) |
| `~/Library/LaunchAgents/com.tessera.tiling.plist` | Login agent: starts the tiling daemon at login (via your granted terminal, on unsigned builds) |
| `~/Library/Logs/Tessera/` | Daemon logs (`daemon.log`, `daemon.err.log`) |
| `~/Library/Application Support/Tessera/` | Menu/tiling agent logs, `daemon.pid`, the app bundle, `auth_start.zsh` launcher |
| `~/.config/tessera/` | Your configuration (`config.json`) — **not** tied to the app install, and preserved across reinstalls |

---

## Uninstall

```bash
tessera-uninstall            # keeps ~/.config/tessera (your settings)
tessera-uninstall --purge    # removes your configuration too
```

If you installed via Homebrew, also remove the formula itself:

```bash
brew uninstall Spidey03/tessera/tessera
```

From a source checkout, the equivalent is `./scripts/uninstall.sh` (plus
`--purge` for the config).

`tessera-uninstall`:

- stops the daemon and menu bar app,
- unloads and deletes both login agents (`com.tessera.menu`, `com.tessera.tiling`),
- deletes the app bundle, launcher, PID file, and logs,
- keeps `~/.config/tessera` unless you pass `--purge`.

---

## Start & stop

### Automatically at login

Both the menu bar app and the tiling daemon start automatically when you log in
(via the two launch agents). The **Start at Login** item in the menu toggles
both agents on/off — it's checked when both are installed.

### From the menu bar icon

Open the status-item menu:

| Menu item | What it does |
|-----------|-------------|
| **Tile Windows Now** | Re-tile everything now |
| **Reload Config** | Re-read `config.json` — live, no restart |
| **Cycle Layout** | Cycle layout mode on the focused display (bsp → master-stack → columns) |
| **Start Daemon** / **Stop Daemon** | Toggle the tiling daemon (menu label matches the current state) |
| **Start at Login** | Toggle auto-start of both login agents |
| **Grant Permissions** ▸ | Open the Accessibility / Input Monitoring panes |
| **Check for Updates…** | Ask GitHub for a newer release now |
| **Automatically Check for Updates** | Auto-check shortly after launch (default on) |
| **Settings…** (`⌘,`) | Open the settings window (edits config, live-reloads) |
| **Open Config File…** | Open `~/.config/tessera/config.json` in your editor |
| **Open Logs Folder** | Reveal the logs folder in Finder |
| **Quit Tessera** (`⌘Q`) | Quit the menu bar app only (daemon keeps running) |

The status icon's dot is **green** while the daemon is running and **gray** when
it is stopped.

### Keyboard / terminal control

- **Quit the daemon** with your quit hotkey (`⌘⌥⇧Q` by default). The daemon is
  **not** auto-relaunched after quitting — it stays stopped until you start it
  again.
- **Start the daemon** from a terminal (must be run from a granted terminal so
  it inherits the grants):

  ```bash
  open -a Terminal "$HOME/Library/Application Support/Tessera/auth_start.zsh"
  ```

  (from a source checkout: `./scripts/auth_start.zsh`)

- **Restart the daemon** by hand:

  ```bash
  launchctl kickstart -k gui/$(id -u)/com.tessera.tiling
  ```

- **Stop / start the login agents** by hand:

  ```bash
  launchctl bootout  gui/$(id -u)/com.tessera.tiling   # stop
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.tessera.tiling.plist   # start
  ```

### Updating

The menu includes a built-in updater. **Check for Updates…** queries the latest
GitHub release; when a newer one is available it offers **Install & Restart**,
which downloads the new bundle into `~/Library/Application Support/Tessera` and
restarts both the daemon and the menu bar app from the new version. When
**Automatically Check for Updates** is on, the same check runs shortly after
launch.

### Logs

| Log | Path |
|-----|------|
| Daemon stdout | `~/Library/Logs/Tessera/daemon.log` |
| Daemon stderr | `~/Library/Logs/Tessera/daemon.err.log` |
| Menu agent | `~/Library/Application Support/Tessera/menu.log` / `menu.err.log` |
| Tiling agent | `~/Library/Application Support/Tessera/tiling.log` / `tiling.err.log` |

---

## Configure

### The settings window

**Settings…** (`⌘,`) in the menu opens a window where you edit the shared
`config.json` keys: gaps, animation, focus-on-new-window, per-app tiling rules,
and hotkeys. Saving reloads the running daemon live. Keys the UI does not edit
(`hotkeys` if untouched, `excludedSubroles`, `multiMonitor`, etc.) are preserved
when you save.

### The config file

The daemon reads `~/.config/tessera/config.json`. The file is created for you on
first run with a commented example config. If you edit it by hand, reload it
live with the menu's **Reload Config** (or restart the daemon).

(`~/.config/tessera/state.json` is runtime state — per-display layout modes,
floating window frames, split weights. It is managed by the daemon; don't
hand-edit it.)

### Key reference

| Key | Default | Meaning |
|-----|---------|---------|
| `gapSize` | `8` | Pixels between windows |
| `outerGap` | `4` | Pixels of outer margin around the tiled area |
| `layoutMode` | `"bsp"` | Default layout: `"bsp"`, `"masterStack"`, or `"columns"` (per-display overrides cycle with `⌘⌥.` and persist in `state.json`) |
| `masterRatio` | `0.6` | Fraction of the screen the master pane gets in `masterStack` mode |
| `splitResizeStep` | `0.10` | How much one `⌘⌥[`/`⌘⌥]` press moves the focused split ratio |
| `splitMinRatio` / `splitMaxRatio` | `0.2` / `0.8` | Range split ratios are clamped to |
| `newWindowFocus` | `false` | `true` = move focus to a newly tiled window |
| `appRules` | `{}` | Per-app rules: `{ "com.bundle.id": "normal" }` — see below |
| `floatingApps` | `[]` | Legacy key; auto-migrated into `appRules` as `"float"` |
| `excludedSubroles` | built-in set | Window subroles never tiled (if present, **replaces** the built-in set entirely) |
| `animationEnabled` | `true` | Animate window moves |
| `animationSteps` | `8` | Animation frame count |
| `animationDuration` | `0.15` | Animation duration in seconds |
| `multiMonitor` | `{ "focusMode": "withinDisplay" }` | How focus navigation behaves across displays |
| `hotkeys` | defaults below | Per-action override: `{ "action": { "keyCode": <int>, "flags": ["cmd", "opt"] } }` — edits via Settings prefer the UI |

### Per-app rules

`appRules` maps an app's bundle ID to one of:

| Rule | Behavior |
|------|----------|
| `normal` | Tiled (default) |
| `float` | Excluded from the BSP tree; keeps its own position/size |
| `ignore` | Completely untouched and invisible to the tiler |
| `sticky` | Tiled, but keeps its tile slot across re-tiles |

### Default hotkeys

| Shortcut | Action |
|----------|--------|
| `⌘⌥⏎` | Tile all windows |
| `⌘⌥H` / `⌘⌥K` | Focus left / previous |
| `⌘⌥J` / `⌘⌥L` | Focus right / next |
| `⌘⌥W` | Remove focused window |
| `⌘⌥F` | Toggle fullscreen |
| `⌘⌥Space` | Toggle split direction (bsp mode) |
| `⌘⌥[` / `⌘⌥]` | Shrink / grow the focused split (bsp mode) |
| `⌘⌥.` | Cycle layout on the focused display: bsp → master-stack → columns |
| `⌘⌥⇧Q` | Quit daemon |

All are remappable in **Settings…** → Hotkeys (click a combo and press the new
keys, or Reset). Overrides are stored under `"hotkeys"` in `config.json`.

---

## Troubleshooting

- **Status dot is gray / windows aren't tiling.** The daemon isn't running.
  Open the menu → **Start Daemon**, then re-tile with `⌘⌥⏎`. If it won't stay
  up, run `tessera-install --check` and read the offending lines.
- **`tessera-install --check` reports "Accessibility grant not detected".**
  Add your terminal under System Settings → Privacy & Security →
  Accessibility and Input Monitoring. The daemon must be started from that
  granted terminal (the login flow / `auth_start.zsh` handle this).
- **Gatekeeper blocks the app** (cask install). Right-click `Tessera.app` in
  Finder → **Open**, and confirm. This is expected for the unsigned release.
- **A Terminal window flashes at login.** Expected on unsigned builds — that's
  the daemon launching through your granted terminal (silent login needs a
  Developer-ID-signed build).
- **You quit the daemon but it starts again.** The menu's **Start at Login** is
  on (agents load at login). Toggle it off if you don't want auto-start, or stop
  only the daemon via **Stop Daemon**.
- **A hotkey doesn't respond.** Check it under **Settings…** → Hotkeys — another
  remap may have claimed that key combination.