import Foundation
import TesseraKit

/// Release version, kept in sync with the Homebrew formula tag (v0.4.0).
let version = "0.4.0"

setbuf(stdout, nil)
setbuf(stderr, nil)

if CommandLine.arguments.contains("--version") {
    print(version)
    exit(0)
}

if CommandLine.arguments.contains("--help") {
    print("""
    Usage: TesseraDaemon [options]

    BSP tiling window manager for macOS.

    Options:
      --version   Print the version and exit.
      --help      Show this help and exit.

    Hotkeys (default, configurable via ~/.config/tessera/config.json):
      ⌘⌥⏎          Tile all windows
      ⌘⌥H / ⌘⌥K    Focus left / previous
      ⌘⌥J / ⌘⌥L    Focus right / next
      ⌘⌥W          Remove focused window
      ⌘⌥F          Fullscreen toggle
      ⌘⌥Space      Toggle split direction
      ⌘⌥[ / ⌘⌥]    Shrink / grow focused split
      ⌘⌥⇧Q         Quit daemon
    """)
    exit(0)
}

print("""
╔══════════════════════════════════════════╗
║         Tessera — Tiling Daemon          ║
╚══════════════════════════════════════════╝
""")

ConfigLoader.ensureConfigDir()
let loaded = ConfigLoader.load()
let tiler = Tiler(config: loaded.tesseraConfig)
let daemon = Daemon(tiler: tiler, bindings: loaded.bindings)
daemon.run()
