/// The two macOS privacy grants the daemon needs.
public enum PermissionGrant: String, CaseIterable, Equatable, Sendable {
    case accessibility
    case inputMonitoring
}

/// Status of one grant as the onboarding checklist sees it. Accessibility can
/// only be granted or not; Input Monitoring can also be `unknown` on macOS
/// versions where `IOHIDCheckAccess` cannot report it.
public enum GrantStatus: Equatable, Sendable {
    case granted
    case notGranted
    case unknown
}

/// One checklist row: what to show and where its button points.
public struct PermissionRow: Equatable, Sendable {
    public let grant: PermissionGrant
    public let title: String
    public let status: GrantStatus
    public let statusText: String
    public let settingsURL: String
}

/// Pure decision logic for the first-run permissions checklist. No AppKit or
/// IOKit here; the menu app probes the system and feeds the results in.
public enum PermissionOnboarding {
    /// UserDefaults key recording that the first-run window has been shown.
    public static let firstLaunchDefaultsKey = "PermissionsOnboardingShown"

    /// Rows are always shown, in this order, so the user sees both grants
    /// and their state at a glance.
    public static let rowOrder: [PermissionGrant] = [.accessibility, .inputMonitoring]

    /// Deep links into the Privacy & Security panes of System Settings.
    public static func settingsURL(for grant: PermissionGrant) -> String {
        switch grant {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
    }

    public static func title(for grant: PermissionGrant) -> String {
        switch grant {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    /// Status line shown beside each row for every granted/unknown/denied case.
    public static func statusText(for grant: PermissionGrant, status: GrantStatus) -> String {
        switch (grant, status) {
        case (_, .granted):
            "Granted"
        case (.accessibility, .notGranted):
            "Not granted: Tessera cannot move or resize windows."
        case (.inputMonitoring, .notGranted):
            "Not granted: Tessera cannot read the tiling hotkeys."
        case (.accessibility, .unknown):
            "Unknown: macOS did not report this grant. Check System Settings."
        case (.inputMonitoring, .unknown):
            "Unknown: this macOS version cannot report Input Monitoring. Check System Settings and confirm your terminal is enabled."
        }
    }

    /// Builds the checklist rows from the probed grant states.
    public static func rows(accessibility: GrantStatus, inputMonitoring: GrantStatus) -> [PermissionRow] {
        rowOrder.map { grant in
            let status = grant == .accessibility ? accessibility : inputMonitoring
            return PermissionRow(
                grant: grant,
                title: title(for: grant),
                status: status,
                statusText: statusText(for: grant, status: status),
                settingsURL: settingsURL(for: grant)
            )
        }
    }

    /// One-line summary at the top of the window.
    public static func summary(accessibility: GrantStatus, inputMonitoring: GrantStatus) -> String {
        if accessibility == .granted && inputMonitoring == .granted {
            return "All permissions granted."
        }
        if accessibility == .notGranted || inputMonitoring == .notGranted {
            return "Permissions still needed. Grant the rows marked Not granted."
        }
        return "Input Monitoring cannot be verified on this macOS version. Confirm it in System Settings."
    }

    /// Shown in the window: grants attach to the launching terminal, not to Tessera.
    public static let terminalCaveat = """
        Grants apply to the terminal that launches the Tessera daemon, not to Tessera itself. \
        On macOS 15 and later, a daemon started by launchd is always denied. Enable your \
        terminal app (for example Terminal.app) under both Accessibility and Input Monitoring.
        """

    /// The window opens automatically only when the flag has never been set.
    public static func shouldShowOnFirstLaunch(hasShownBefore: Bool) -> Bool {
        !hasShownBefore
    }
}
