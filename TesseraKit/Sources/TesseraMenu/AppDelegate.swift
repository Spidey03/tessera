import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var control: DaemonControl!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        control = DaemonControl()
        statusItemController = StatusItemController(control: control)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSStatusBar.system.removeStatusItem(statusItemController.statusItem)
    }
}