import AppKit

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSStatusBar.system.removeStatusItem(statusItemController.statusItem)
    }
}