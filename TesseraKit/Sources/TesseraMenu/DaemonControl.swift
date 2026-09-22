import AppKit
import Foundation

/// Paths and control plumbing shared with the Tessera daemon:
///  - raw file paths (PID file, config, logs)
///  - daemon start/stop + start-at-login via launchctl
///  - one-way commands over DistributedNotificationCenter
final class DaemonControl: NSObject, @unchecked Sendable {
    private let appSupportDir: URL
    private let pidFileURL: URL
    private let configURL: URL
    private let logsURL: URL
    private let menuAgentPlist: URL
    private let tilingAgentPlist: URL

    /// Retained observer tokens (DistributedNotificationCenter requires the
    /// returned token to be kept alive or the observation is silently dropped).
    private var startObserver: NSObjectProtocol?
    private var quitObserver: NSObjectProtocol?

    /// Periodically re-check the PID file so the dot stays accurate between
    /// menu opens / notification delivery.
    private var pollTimer: Timer?

    /// The daemon process we spawned. Retained so the child stays a child
    /// (TCC grants inherit down the parent chain) and to know when it exits.
    private var daemonProcess: Process?

    /// The daemon lives inside the app bundle next to the menu executable so
    /// the child inherits the bundle's accessibility/input-monitoring trust.
    private var daemonBinaryURL: URL {
        appSupportDir.appendingPathComponent("Tessera.app/Contents/MacOS/TesseraDaemon")
    }

    /// Called whenever running state or start-at-login state may have changed.
    var onStatusChange: (() -> Void)?

    override init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        appSupportDir = home.appendingPathComponent("Library/Application Support/Tessera")
        pidFileURL = appSupportDir.appendingPathComponent("daemon.pid")
        configURL = home.appendingPathComponent(".config/tessera/config.json")
        logsURL = home.appendingPathComponent("Library/Logs/Tessera")
        menuAgentPlist = home.appendingPathComponent("Library/LaunchAgents/com.tessera.menu.plist")
        tilingAgentPlist = home.appendingPathComponent("Library/LaunchAgents/com.tessera.tiling.plist")
        super.init()

        let nc = DistributedNotificationCenter.default()
        startObserver = nc.addObserver(forName: Self.daemonDidStart, object: nil, queue: .main) { [weak self] _ in
            self?.onStatusChange?()
        }
        quitObserver = nc.addObserver(forName: Self.daemonDidQuit, object: nil, queue: .main) { [weak self] _ in
            self?.onStatusChange?()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.onStatusChange?()
        }
    }

    static let daemonCommand = Notification.Name("TesseraDaemonCommand")
    static let daemonDidStart = Notification.Name("TesseraDaemonDidStart")
    static let daemonDidQuit = Notification.Name("TesseraDaemonDidQuit")

    // MARK: - State

    var daemonPID: Int? {
        guard let text = try? String(contentsOf: pidFileURL, encoding: .utf8),
              let pid = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return pid
    }

    /// True when the daemon PID file points at a live process.
    var isRunning: Bool {
        guard let pid = daemonPID else { return false }
        return kill(pid_t(pid), 0) == 0
    }

    /// "Start at login" is on when the menu agent plist is installed.
    var isStartAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: menuAgentPlist.path)
    }

    var hasDaemonAgent: Bool {
        let agent = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.tessera.daemon.plist")
        return FileManager.default.fileExists(atPath: agent.path)
    }

    var configFileURL: URL { configURL }
    var logDirectoryURL: URL { logsURL }

    // MARK: - Commands

    func send(_ action: String) {
        DistributedNotificationCenter.default().post(
            name: Self.daemonCommand,
            object: nil,
            userInfo: ["action": action]
        )
    }

    /// Spawn the installed daemon binary as a child of the menu app.
    ///
    /// Deliberately NOT a separate LaunchAgent: TCC accessibility/input-monitoring
    /// grants are inherited down the parent chain, but macOS ignores them for a
    /// bare daemon binary spawned directly by launchd. Keeping it our child means
    /// the user grants permissions to the menu app once and the daemon inherits.
    func startDaemon() {
        guard !isRunning, daemonProcess == nil else { return }
        let binary = daemonBinaryURL
        guard FileManager.default.fileExists(atPath: binary.path) else { return }

        let process = Process()
        process.executableURL = binary

        // Append to the shared daemon logs (create the folder on first run).
        // O_APPEND keeps concurrent writers from clobbering each other's offsets.
        let fm = FileManager.default
        if !fm.fileExists(atPath: logsURL.path) {
            try? fm.createDirectory(at: logsURL, withIntermediateDirectories: true)
        }
        let outFD = Darwin.open(logsURL.appendingPathComponent("daemon.log").path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        if outFD >= 0 {
            process.standardOutput = FileHandle(fileDescriptor: outFD, closeOnDealloc: true)
        }
        let errFD = Darwin.open(logsURL.appendingPathComponent("daemon.err.log").path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        if errFD >= 0 {
            process.standardError = FileHandle(fileDescriptor: errFD, closeOnDealloc: true)
        }

        process.terminationHandler = { [weak self, weak process] _ in
            guard let self, let process, self.daemonProcess === process else { return }
            self.daemonProcess = nil
            self.onStatusChange?()
        }

        do {
            try process.run()
            daemonProcess = process
            print("[menu] spawned daemon (pid \(process.processIdentifier))")
        } catch {
            print("[menu] failed to spawn daemon: \(error)")
            return
        }
        onStatusChange?()
    }

    func stopDaemon() {
        send("quit")
    }

    // MARK: - Start at login (com.tessera.menu + com.tessera.tiling agents)

    func setStartAtLogin(_ enabled: Bool) {
        if enabled {
            prepareAuthStartScript()
            writeMenuAgentPlist()
            writeTilingAgentPlist()
            _ = launchctl("bootstrap", ["gui/\(getuid())", menuAgentPlist.path])
            _ = launchctl("bootstrap", ["gui/\(getuid())", tilingAgentPlist.path])
        } else {
            _ = launchctl("bootout", ["gui/\(getuid())/com.tessera.menu"])
            _ = launchctl("bootout", ["gui/\(getuid())/com.tessera.tiling"])
            try? FileManager.default.removeItem(at: menuAgentPlist)
            try? FileManager.default.removeItem(at: tilingAgentPlist)
        }
        // A running daemon is left alone: this only controls login startups.
        onStatusChange?()
    }

    /// The stable location the tiling agent points at. The script is copied
    /// from the app bundle so it never depends on where the repo lives.
    private var authStartScriptURL: URL {
        appSupportDir.appendingPathComponent("auth_start.zsh")
    }

    private func prepareAuthStartScript() {
        let fm = FileManager.default
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("auth_start.zsh"),
           fm.fileExists(atPath: resource.path),
           let data = try? Data(contentsOf: resource) {
            try? fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            try? data.write(to: authStartScriptURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: authStartScriptURL.path)
        } else if !fm.fileExists(atPath: authStartScriptURL.path) {
            print("[menu] warning: bundled auth_start.zsh unavailable; tiling agent won't start the daemon")
        }
    }

    private func writeMenuAgentPlist() {
        let appURL = appSupportDir.appendingPathComponent("Tessera.app")
        let plist: [String: Any] = [
            "Label": "com.tessera.menu",
            // Launch via LaunchServices so the bundle starts as a proper GUI app.
            // (This does NOT unlock TCC — see scripts/auth_start.zsh — it just
            // keeps the menu bar app running.)
            "ProgramArguments": ["/usr/bin/open", "-n", appURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "StandardOutPath": appSupportDir.appendingPathComponent("menu.log").path,
            "StandardErrorPath": appSupportDir.appendingPathComponent("menu.err.log").path,
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try? data?.write(to: menuAgentPlist, options: .atomic)
    }

    private func writeTilingAgentPlist() {
        // Launch style depends on how the installed bundle is signed:
        //  - Developer ID signed -> launchd runs the daemon directly. Its
        //    Apple-issued TeamIdentifier is what macOS TCC attributes grants
        //    to, so login is fully silent (no Terminal window, issue #13).
        //  - unsigned/ad-hoc     -> start through Terminal.app (-gj, hidden):
        //    the only lineage whose Accessibility/Input Monitoring grants
        //    survive; launchd children of an unsigned binary are always denied.
        let program: [String]
        if isDeveloperIDSigned() {
            program = [daemonBinaryURL.path]
        } else {
            program = ["/usr/bin/open", "-gj", "-a", "Terminal", authStartScriptURL.path]
        }
        let plist: [String: Any] = [
            "Label": "com.tessera.tiling",
            "ProgramArguments": program,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "StandardOutPath": appSupportDir.appendingPathComponent("tiling.log").path,
            "StandardErrorPath": appSupportDir.appendingPathComponent("tiling.err.log").path,
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: tilingAgentPlist, options: .atomic)
    }

    /// True when the installed app bundle carries an Apple "Developer ID
    /// Application" code signature (TeamIdentifier — what TCC trusts).
    private func isDeveloperIDSigned() -> Bool {
        let app = appSupportDir.appendingPathComponent("Tessera.app")
        guard FileManager.default.fileExists(atPath: app.path) else { return false }
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["-dv", app.path]
        let errPipe = Pipe()
        codesign.standardError = errPipe
        codesign.standardOutput = FileHandle.nullDevice
        do {
            try codesign.run()
            codesign.waitUntilExit()
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .contains("Authority=Developer ID Application") ?? false
        } catch {
            return false
        }
    }

    // MARK: - Open helpers

    func openConfig() {
        let fm = FileManager.default
        if fm.fileExists(atPath: configURL.path) {
            NSWorkspace.shared.open(configURL)
        } else {
            NSWorkspace.shared.open(configURL.deletingLastPathComponent())
        }
    }

    func openLogs() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logsURL.path) {
            try? fm.createDirectory(at: logsURL, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(logsURL)
    }

    func openAccessibilityPreferencePane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringPreferencePane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - launchctl

    @discardableResult
    private func launchctl(_ subcommand: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [subcommand] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}