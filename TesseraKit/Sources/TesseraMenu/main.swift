import AppKit
import Foundation

/// Release version, kept in sync with the daemon and Homebrew formula tag (v0.4.0).
let tesseraMenuVersion = "0.4.0"

setbuf(stdout, nil)
setbuf(stderr, nil)

if CommandLine.arguments.contains("--version") {
    print(tesseraMenuVersion)
    exit(0)
}

if CommandLine.arguments.contains("--help") {
    print("""
    Usage: TesseraMenu [options]

    Menu bar companion for the Tessera tiling daemon.

    Options:
      --version        Print the version and exit.
      --help           Show this help and exit.
      --show-settings  Open the settings window immediately on launch.
    """)
    exit(0)
}

// Keep out of the Dock — menu bar accessory only.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate(showSettingsOnLaunch: CommandLine.arguments.contains("--show-settings"))
app.delegate = delegate
app.run()