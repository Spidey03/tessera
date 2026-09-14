import AppKit

/// Builds and manages the status item + menu. Re-renders state whenever the
/// daemon starts/stops or the menu is about to open.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let control: DaemonControl
    let statusItem: NSStatusItem
    private var settingsController: SettingsWindowController?

    // Dynamic menu items refreshed in refresh()
    private let startStopItem = NSMenuItem(title: "", action: #selector(toggleStartStop), keyEquivalent: "")
    private let tileItem = NSMenuItem(title: "Tile Windows Now", action: #selector(tileNow), keyEquivalent: "")
    private let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "")
    private let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")

    init(control: DaemonControl) {
        self.control = control
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.split.2x2", accessibilityDescription: "Tessera")
            button.imagePosition = .imageOnly
            button.toolTip = "Tessera"
        }

        let menu = NSMenu()
        menu.delegate = self
        for item in [tileItem, reloadItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        startAtLoginItem.target = self
        startAtLoginItem.state = control.isStartAtLoginEnabled ? .on : .off
        menu.addItem(startAtLoginItem)
        startStopItem.target = self
        menu.addItem(startStopItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)
        let openConfigItem = NSMenuItem(title: "Open Config File…", action: #selector(openConfig), keyEquivalent: "")
        openConfigItem.target = self
        menu.addItem(openConfigItem)
        let openLogsItem = NSMenuItem(title: "Open Logs Folder", action: #selector(openLogs), keyEquivalent: "")
        openLogsItem.target = self
        menu.addItem(openLogsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Tessera", action: #selector(quitMenuBarApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)
        menu.addItem(.separator())

        let versionItem = NSMenuItem(title: "Tessera \(tesseraMenuVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        statusItem.menu = menu

        control.onStatusChange = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        let running = control.isRunning
        let color: NSColor = running ? .systemGreen : .systemGray
        statusItem.button?.contentTintColor = color

        tileItem.isEnabled = running
        reloadItem.isEnabled = running
        startStopItem.title = running ? "Stop Daemon" : "Start Daemon"
        startStopItem.isEnabled = true
        startAtLoginItem.state = control.isStartAtLoginEnabled ? .on : .off
        statusItem.button?.toolTip = running ? "Tessera — running" : "Tessera — stopped"
    }

    // MARK: - Actions

    @objc private func tileNow() {
        control.send("tile")
    }

    @objc private func reloadConfig() {
        control.send("reload")
    }

    @objc private func toggleStartStop() {
        if control.isRunning {
            control.stopDaemon()
        } else {
            control.startDaemon()
        }
    }

    @objc private func openConfig() {
        control.openConfig()
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    func showSettingsWindow() {
        if settingsController == nil {
            let settings = ConfigSettings(configURL: control.configFileURL)
            settingsController = SettingsWindowController(settings: settings, daemonControl: control)
        }
        settingsController?.showSettings()
    }

    @objc private func openLogs() {
        control.openLogs()
    }

    @objc private func toggleStartAtLogin() {
        control.setStartAtLogin(!control.isStartAtLoginEnabled)
    }

    @objc private func quitMenuBarApp() {
        NSApp.terminate(nil)
    }
}