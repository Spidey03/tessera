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

    /// Called whenever running state or start-at-login state may have changed.
    var onStatusChange: (() -> Void)?

    override init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        appSupportDir = home.appendingPathComponent("Library/Application Support/Tessera")
        pidFileURL = appSupportDir.appendingPathComponent("daemon.pid")
        configURL = home.appendingPathComponent(".config/tessera/config.json")
        logsURL = home.appendingPathComponent("Library/Logs/Tessera")
        menuAgentPlist = home.appendingPathComponent("Library/LaunchAgents/com.tessera.menu.plist")
        super.init()

        let nc = DistributedNotificationCenter.default()
        nc.addObserver(forName: Self.daemonDidStart, object: nil, queue: .main) { [weak self] _ in
            self?.onStatusChange?()
        }
        nc.addObserver(forName: Self.daemonDidQuit, object: nil, queue: .main) { [weak self] _ in
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

    // MARK: - Commands

    func send(_ action: String) {
        DistributedNotificationCenter.default().post(
            name: Self.daemonCommand,
            object: nil,
            userInfo: ["action": action]
        )
    }

    /// Start the daemon: prefer the LaunchAgent (install_daemon.sh), otherwise
    /// spawn the installed binary directly.
    func startDaemon() {
        guard !isRunning else { return }

        let agentPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.tessera.daemon.plist")
        if FileManager.default.fileExists(atPath: agentPlist.path) {
            _ = launchctl("bootstrap", ["gui/\(getuid())", agentPlist.path])
            _ = launchctl("kickstart", ["gui/\(getuid())/com.tessera.daemon"])
        } else {
            let binary = appSupportDir.appendingPathComponent("TesseraDaemon")
            if FileManager.default.fileExists(atPath: binary.path) {
                let process = Process()
                process.executableURL = binary
                try? process.run()
            }
        }
        onStatusChange?()
    }

    func stopDaemon() {
        send("quit")
    }

    // MARK: - Start at login (com.tessera.menu agent)

    func setStartAtLogin(_ enabled: Bool) {
        if enabled {
            writeMenuAgentPlist()
            _ = launchctl("bootstrap", ["gui/\(getuid())", menuAgentPlist.path])
        } else {
            _ = launchctl("bootout", ["gui/\(getuid())/com.tessera.menu"])
            try? FileManager.default.removeItem(at: menuAgentPlist)
        }
        onStatusChange?()
    }

    private func writeMenuAgentPlist() {
        let plist: [String: Any] = [
            "Label": "com.tessera.menu",
            "ProgramArguments": [appSupportDir.appendingPathComponent("TesseraMenu").path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "StandardOutPath": logsURL.appendingPathComponent("menu.log").path,
            "StandardErrorPath": logsURL.appendingPathComponent("menu.err.log").path,
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try? data?.write(to: menuAgentPlist, options: .atomic)
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