import ApplicationServices
import Foundation
import TesseraSystem

func printBanner() {
    print("""
    ╔══════════════════════════════════════════╗
    ║      Tessera — Window Discovery          ║
    ╚══════════════════════════════════════════╝
    """)
}

func printWarning() {
    print("⚠️  Note: macOS Accessibility permissions required.")
    print("   Grant access in System Settings → Privacy & Security →")
    print("   Accessibility → Add Terminal (or your IDE)")
    print()
}

func printWindows(_ windows: [MacWindow]) {
    if windows.isEmpty {
        print("No windows found. You may need to grant Accessibility permissions.")
        return
    }

    let grouped = Dictionary(grouping: windows) { $0.appName }
    let sortedApps = grouped.keys.sorted()

    for appName in sortedApps {
        let appWindows = grouped[appName]!
        let pid = appWindows.first!.appPID
        let focusedCount = appWindows.filter(\.isFocused).count
        let globalFocusedCount = appWindows.filter(\.isGloballyFocused).count
        print("\(appName) [PID: \(pid)] — \(appWindows.count) window(s)", globalFocusedCount > 0 ? "★" : focusedCount > 0 ? "☆" : "")

        for (i, win) in appWindows.enumerated() {
            let marker: String
            if win.isGloballyFocused {
                marker = " ◀ global focus"
            } else if win.isFocused {
                marker = " ◀ app focus"
            } else {
                marker = ""
            }
            print("  └─ #\(i + 1): \(Int(win.position.x)),\(Int(win.position.y)) \(Int(win.size.width))x\(Int(win.size.height)) \"\(win.title)\"\(marker)")
        }
    }
}

printBanner()

let trusted = AXIsProcessTrusted()
if !trusted {
    printWarning()
    print("ℹ️  Run this once to trigger the permission prompt:")
    print("   Then grant access in System Settings → Privacy & Security → Accessibility")
    print()
}

let windows = WindowDiscovery.allWindows()

if !trusted && windows.isEmpty {
    print("⚠️  No windows found (AX not trusted). Grant permission and re-run.")
} else {
    printWindows(windows)
    print("\nTotal: \(windows.count) window(s) across \(Set(windows.map(\.appName)).count) app(s)")
}
