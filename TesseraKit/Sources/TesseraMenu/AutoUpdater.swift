import AppKit
import Foundation
import TesseraKit

/// Manual + automatic update flow: discover the latest release, prompt, stage
/// the download, and hand off to a detached helper that swaps the bundle while
/// the menu app (and daemon) restart.
@MainActor
final class AutoUpdater {
    private static let autoCheckKey = "TesseraCheckUpdatesAutomatically"

    /// The folder that holds Tessera.app (its parent bundle dir when installed
    /// via `~/Library/Application Support/Tessera`).
    private var supportDir: URL {
        Bundle.main.bundleURL.deletingLastPathComponent()
    }

    var automaticChecksEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoCheckKey) } // defaults true
        set { UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey) }
    }

    private var checkInFlight = false
    private(set) var pendingUpdate: UpdateReleaseInfo?

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? tesseraMenuVersion
    }

    func startAutomaticCheck() {
        guard automaticChecksEnabled else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.check(showUpToDate: false)
        }
    }

    func checkNow() {
        Task { [weak self] in
            await self?.check(showUpToDate: true)
        }
    }

    private func check(showUpToDate: Bool) async {
        guard !checkInFlight else { return }
        checkInFlight = true
        defer { checkInFlight = false }
        do {
            if let info = try await UpdateChecker.fetchLatestReleaseInfo(currentVersion: currentVersion) {
                pendingUpdate = info
                promptInstall(info)
            } else {
                pendingUpdate = nil
                if showUpToDate {
                    showAlert(message: "Tessera is up to date (v\(currentVersion)).", informative: "No newer release was found.")
                }
            }
        } catch {
            pendingUpdate = nil
            if showUpToDate {
                showAlert(message: "Update check failed.", informative: error.localizedDescription)
            }
        }
    }

    private func promptInstall(_ info: UpdateReleaseInfo) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Tessera \(info.version) is available"
        alert.informativeText = "You have v\(currentVersion). Download and install now?\(info.size > 0 ? " (\(Int(info.size) / 1_048_576) MB)" : "")"
        alert.addButton(withTitle: "Install & Restart")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(info)
    }

    private func install(_ info: UpdateReleaseInfo) {
        showAlert(message: "Downloading Tessera \(info.version)…", informative: "The app restarts automatically when the download finishes.")
        Task { [weak self] in
            do {
                let zip = try await AppInstaller.download(info)
                let staged = try AppInstaller.stage(zipURL: zip)
                await self?.restartWith(stagedApp: staged)
            } catch {
                self?.showAlert(message: "Update failed.", informative: "\(error)")
            }
        }
    }

    /// Swap in the staged bundle from a detached shell (sleeps 2s so this app
    /// and the daemon can exit), then restart the tiling daemon + menu.
    private func restartWith(stagedApp: URL) {
        let support = supportDir.path
        let old = support + "/Tessera.old"
        let staged = stagedApp.path
        let script = """
        sleep 2
        APPSUP="\(support)"
        OLDDIR="\(old)"
        /usr/bin/pkill -f "$APPSUP/Tessera.app/Contents/MacOS/TesseraDaemon" >/dev/null 2>&1 || true
        /bin/rm -rf "$OLDDIR"
        [ -d "$APPSUP/Tessera.app" ] && /bin/mv "$APPSUP/Tessera.app" "$OLDDIR" || true
        /bin/mv "\(staged)" "$APPSUP/Tessera.app"
        /bin/launchctl kickstart -k "gui/$(id -u)/com.tessera.tiling" >/dev/null 2>&1 || true
        /usr/bin/open "$APPSUP/Tessera.app" >/dev/null 2>&1 || true
        /bin/rm -rf "$OLDDIR" 2>/dev/null || true
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            showAlert(message: "Update failed.", informative: "Could not launch the installer: \(error)")
            return
        }
        NSApp.terminate(nil)
    }

    private func showAlert(message: String, informative: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}