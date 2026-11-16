import AppKit
import ApplicationServices
import IOKit.hid
import TesseraKit

/// Reads the two grants without prompting. `AXIsProcessTrusted()` and
/// `IOHIDCheckAccess` both report state only; neither shows a system dialog.
enum PermissionProbe {
    static func accessibility() -> GrantStatus {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    static func inputMonitoring() -> GrantStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .notGranted
        default: .unknown
        }
    }
}

/// Small checklist window: status of each grant, a button per grant that opens
/// the matching System Settings pane, and the terminal-lineage caveat.
@MainActor
final class PermissionsOnboardingWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private var statusLabels: [PermissionGrant: NSTextField] = [:]

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Tessera"
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        window.contentView = buildContent()
        window.center()
    }

    /// Refreshes status and brings the window forward. Called on first launch
    /// and from the "Setup Permissions…" menu item.
    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Re-probe whenever the window regains focus, since the user has usually
    /// just toggled a switch in System Settings.
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    private func refresh() {
        let accessibility = PermissionProbe.accessibility()
        let inputMonitoring = PermissionProbe.inputMonitoring()
        summaryLabel.stringValue = PermissionOnboarding.summary(
            accessibility: accessibility, inputMonitoring: inputMonitoring)
        for row in PermissionOnboarding.rows(accessibility: accessibility, inputMonitoring: inputMonitoring) {
            statusLabels[row.grant]?.stringValue = row.statusText
            statusLabels[row.grant]?.textColor = row.status == .granted ? .systemGreen : .secondaryLabelColor
        }
    }

    private func buildContent() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let heading = NSTextField(labelWithString: "Tessera needs two macOS permissions")
        heading.font = .boldSystemFont(ofSize: 15)
        root.addArrangedSubview(heading)

        summaryLabel.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(summaryLabel)

        for grant in PermissionOnboarding.rowOrder {
            root.addArrangedSubview(makeRowView(for: grant))
        }

        let caveat = NSTextField(wrappingLabelWithString: PermissionOnboarding.terminalCaveat)
        caveat.font = .systemFont(ofSize: 11)
        caveat.textColor = .secondaryLabelColor
        root.addArrangedSubview(caveat)

        let note = NSTextField(wrappingLabelWithString: "If a grant shows Unknown, check its switch in System Settings directly.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)

        refresh()
        return root
    }

    private func makeRowView(for grant: PermissionGrant) -> NSView {
        let name = NSTextField(labelWithString: PermissionOnboarding.title(for: grant))
        name.font = .systemFont(ofSize: 13, weight: .semibold)

        let status = NSTextField(wrappingLabelWithString: "")
        status.font = .systemFont(ofSize: 12)
        status.preferredMaxLayoutWidth = 300
        statusLabels[grant] = status

        let button = NSButton(title: "Open System Settings…", target: self, action: #selector(openPane(_:)))
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(grant.rawValue)

        let text = NSStackView(views: [name, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4

        let line = NSStackView(views: [text, button])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 12
        return line
    }

    @objc private func openPane(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let grant = PermissionGrant(rawValue: raw),
              let url = URL(string: PermissionOnboarding.settingsURL(for: grant)) else { return }
        NSWorkspace.shared.open(url)
    }
}
