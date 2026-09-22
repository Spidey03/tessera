import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var control: DaemonControl!
    private var statusItemController: StatusItemController!
    private let showSettingsOnLaunch: Bool

    init(showSettingsOnLaunch: Bool = false) {
        self.showSettingsOnLaunch = showSettingsOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        control = DaemonControl()
        statusItemController = StatusItemController(control: control)
        if showSettingsOnLaunch {
            statusItemController.showSettingsWindow()
        }
        // Auto-start the daemon only when the menu itself runs under a granted
        // parent (e.g. launched from a permissioned Terminal). When the menu is
        // a launchd/LaunchServices child (start-at-login) it is NOT trusted —
        // spawning its own daemon would just produce a pidfile-clobbering,
        // permission-less zombie with no tiling. The tiling daemon is instead
        // started at login through Terminal (see scripts/auth_start.zsh).
        if AXIsProcessTrusted() && !control.isRunning {
            control.startDaemon()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // When the menu app quits, cleanly shut down the daemon so it
        // doesn't linger as an orphaned launchd child without trust.
        control.send("quit")
        NSStatusBar.system.removeStatusItem(statusItemController.statusItem)
    }
}