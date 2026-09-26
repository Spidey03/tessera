import AppKit
import TesseraUI

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
    private let cycleLayoutItem = NSMenuItem(title: "Cycle Layout", action: #selector(cycleLayout), keyEquivalent: "")
    private let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
    private let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    private let autoCheckItem = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutoCheck), keyEquivalent: "")
    private let versionItem = NSMenuItem(title: "Tessera \(tesseraMenuVersion)", action: nil, keyEquivalent: "")
    private let updates = AutoUpdater()

    init(control: DaemonControl) {
        self.control = control
        // Not NSStatusItem.squareLength: at 22 pt the 13 pt glyph sat behind
        // 4.5 pt of dead space on each side. The length has to stay at or above
        // TesseraMenuIcon.statusItemCanvas or the image gets scaled down to fit.
        self.statusItem = NSStatusBar.system.statusItem(withLength: TesseraMenuIcon.statusItemLength)

        super.init()

        if let button = statusItem.button {
            button.image = TesseraMenuIcon.statusImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Tessera"
        }

        let menu = NSMenu()
        menu.delegate = self
        for item in [tileItem, reloadItem, cycleLayoutItem] {
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

        let permItem = NSMenuItem(title: "Grant Permissions", action: nil, keyEquivalent: "")
        let permMenu = NSMenu()
        let permItems: [(String, Selector)] = [
            ("Accessibility…", #selector(openAccessibilitySettings)),
            ("Input Monitoring…", #selector(openInputMonitoringSettings)),
        ]
        for (title, action) in permItems {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            permMenu.addItem(item)
        }
        permItem.submenu = permMenu
        menu.addItem(permItem)

        menu.addItem(.separator())
        checkForUpdatesItem.target = self
        autoCheckItem.target = self
        menu.addItem(checkForUpdatesItem)
        menu.addItem(autoCheckItem)
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
        // Deliberately no `contentTintColor` here: a tint replaces the menu
        // bar's automatic foreground, so the glyph would stop switching with a
        // wallpaper-following menu bar and look out of place next to the
        // monochrome icons beside it. `appearsDisabled` gives the stopped
        // state the system's own dimmed treatment in light and dark alike,
        // while leaving the item fully clickable.
        statusItem.button?.appearsDisabled = !running

        tileItem.isEnabled = running
        reloadItem.isEnabled = running
        cycleLayoutItem.isEnabled = running
        startStopItem.title = running ? "Stop Daemon" : "Start Daemon"
        startStopItem.isEnabled = true
        startAtLoginItem.state = control.isStartAtLoginEnabled ? .on : .off
        statusItem.button?.toolTip = running ? "Tessera — running" : "Tessera — stopped"

        autoCheckItem.state = updates.automaticChecksEnabled ? .on : .off
        versionItem.title = updates.pendingUpdate != nil
            ? "Tessera \(tesseraMenuVersion) — update v\(updates.pendingUpdate!.version) available"
            : "Tessera \(tesseraMenuVersion)"
    }

    /// Run a background update check shortly after launch (when enabled) and
    /// again each time the menu opens (throttled by the in-flight guard).
    func startAutomaticUpdateChecks() {
        updates.startAutomaticCheck()
    }

    // MARK: - Actions

    @objc private func tileNow() {
        control.send("tile")
    }

    @objc private func cycleLayout() {
        control.send("cycleLayout")
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

    @objc private func openAccessibilitySettings() {
        control.openAccessibilityPreferencePane()
    }

    @objc private func openInputMonitoringSettings() {
        control.openInputMonitoringPreferencePane()
    }

    @objc private func toggleStartAtLogin() {
        control.setStartAtLogin(!control.isStartAtLoginEnabled)
    }

    @objc private func quitMenuBarApp() {
        NSApp.terminate(nil)
    }

    @objc private func checkForUpdates() {
        updates.checkNow()
    }

    @objc private func toggleAutoCheck() {
        updates.automaticChecksEnabled.toggle()
        autoCheckItem.state = updates.automaticChecksEnabled ? .on : .off
    }
}