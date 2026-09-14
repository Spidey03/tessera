import AppKit
import TesseraKit

/// Modal-ish settings window editing `~/.config/tessera/config.json`.
/// On save it writes the file and tells the daemon to reload via IPC.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: ConfigSettings
    private let daemonControl: DaemonControl

    private let gapSizeField = NSTextField(string: "")
    private let outerGapField = NSTextField(string: "")
    private let newWindowFocusCheck = NSButton(checkboxWithTitle: "Focus the newly added window", target: nil, action: nil)
    private let animationEnabledCheck = NSButton(checkboxWithTitle: "Animate window movement", target: nil, action: nil)
    private let animationStepsField = NSTextField(string: "")
    private let animationDurationField = NSTextField(string: "")

    private let rulesStack = NSStackView()
    private var ruleRows: [(field: NSTextField, popup: NSPopUpButton)] = []

    private let statusLabel = NSTextField(labelWithString: "")

    private let allRules: [AppTilingRule] = [.normal, .ignore, .float, .sticky]

    init(settings: ConfigSettings, daemonControl: DaemonControl) {
        self.settings = settings
        self.daemonControl = daemonControl

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tessera Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.contentView = buildContentView()
        window.delegate = self
        padWindowHeight()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showSettings() {
        window?.center()
        loadValues()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Gap between windows (px):"), gapSizeField],
            [NSTextField(labelWithString: "Outer gap (px):"), outerGapField],
            [NSTextField(labelWithString: "Animation steps:"), animationStepsField],
            [NSTextField(labelWithString: "Animation duration (s):"), animationDurationField],
        ])
        for field in [gapSizeField, outerGapField, animationStepsField, animationDurationField] {
            field.widthAnchor.constraint(equalToConstant: 120).isActive = true
        }
        root.addArrangedSubview(grid)

        newWindowFocusCheck.target = self
        animationEnabledCheck.target = self
        root.addArrangedSubview(newWindowFocusCheck)
        root.addArrangedSubview(animationEnabledCheck)
        root.setCustomSpacing(14, after: animationEnabledCheck)

        root.addArrangedSubview(sectionLabel("Per-app tiling rules"))

        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 6
        rulesStack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.documentView = rulesStack
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        NSLayoutConstraint.activate([
            rulesStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            rulesStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            rulesStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 150),
            scroll.widthAnchor.constraint(equalToConstant: 428),
        ])
        root.addArrangedSubview(scroll)

        let addButton = NSButton(title: "+ Add Rule", target: self, action: #selector(addRule))
        let rowButtons = NSStackView(views: [addButton])
        rowButtons.orientation = .horizontal
        rowButtons.spacing = 8
        root.addArrangedSubview(rowButtons)

        let saveButton = NSButton(title: "Save & Reload", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        statusLabel.textColor = .secondaryLabelColor
        let bottom = NSStackView(views: [saveButton, statusLabel])
        bottom.orientation = .horizontal
        bottom.spacing = 12
        bottom.alignment = .centerY
        root.addArrangedSubview(bottom)

        return root
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Grow the window to fit content after building (auto layout has no fixed height).
    private func padWindowHeight() {
        window?.layoutIfNeeded()
        if let content = window?.contentView {
            let height = content.fittingSize.height + 4
            window?.setContentSize(NSSize(width: 480, height: height))
        }
    }

    // MARK: - Data <-> UI

    private func loadValues() {
        gapSizeField.stringValue = String(format: "%.1f", settings.gapSize)
        outerGapField.stringValue = String(format: "%.1f", settings.outerGap)
        newWindowFocusCheck.state = settings.newWindowFocus ? .on : .off
        animationEnabledCheck.state = settings.animationEnabled ? .on : .off
        animationStepsField.stringValue = "\(settings.animationSteps)"
        animationDurationField.stringValue = String(format: "%.2f", settings.animationDuration)

        for (bundleID, rule) in settings.appRules.sorted(by: { $0.key < $1.key }) {
            addRuleRow(bundleID: bundleID, rule: rule)
        }
        if ruleRows.isEmpty {
            addRuleRow(bundleID: "", rule: .normal)
        }
        statusLabel.stringValue = ""
    }

    private func addRuleRow(bundleID: String, rule: AppTilingRule) {
        let field = NSTextField(string: bundleID)
        field.placeholderString = "com.example.app"
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let popup = NSPopUpButton()
        for r in allRules {
            popup.addItem(withTitle: r.rawValue)
        }
        popup.selectItem(withTitle: rule.rawValue)
        popup.controlSize = .small

        let removeButton = NSButton(title: "–", target: self, action: #selector(removeRule))
        removeButton.bezelStyle = .rounded
        removeButton.tag = ruleRows.count

        let row = NSStackView(views: [field, popup, removeButton])
        row.orientation = .horizontal
        row.spacing = 8
        rulesStack.addArrangedSubview(row)
        ruleRows.append((field: field, popup: popup))
        for i in 0..<ruleRows.count {
            if let button = rulesStack.arrangedSubviews[i].subviews.compactMap({ $0 as? NSButton }).first {
                button.tag = i
            }
        }
    }

    @objc private func addRule() {
        addRuleRow(bundleID: "", rule: .normal)
    }

    @objc private func removeRule(_ sender: NSButton) {
        guard ruleRows.indices.contains(sender.tag) else { return }
        let removed = rulesStack.arrangedSubviews[sender.tag]
        ruleRows.remove(at: sender.tag)
        rulesStack.removeArrangedSubview(removed)
        removed.removeFromSuperview()
        for i in 0..<ruleRows.count {
            if let button = rulesStack.arrangedSubviews[i].subviews.compactMap({ $0 as? NSButton }).first {
                button.tag = i
            }
        }
        if ruleRows.isEmpty { addRuleRow(bundleID: "", rule: .normal) }
    }

    // MARK: - Save

    @objc private func save() {
        guard let gap = Double(gapSizeField.stringValue.trimmingCharacters(in: .whitespaces)),
              let outer = Double(outerGapField.stringValue.trimmingCharacters(in: .whitespaces)),
              let steps = Int(animationStepsField.stringValue.trimmingCharacters(in: .whitespaces)),
              let duration = Double(animationDurationField.stringValue.trimmingCharacters(in: .whitespaces)) else {
            statusLabel.stringValue = "Invalid number."
            return
        }

        settings.gapSize = gap
        settings.outerGap = outer
        settings.newWindowFocus = newWindowFocusCheck.state == .on
        settings.animationEnabled = animationEnabledCheck.state == .on
        settings.animationSteps = steps
        settings.animationDuration = duration

        var rules: [String: AppTilingRule] = [:]
        for (field, popup) in ruleRows {
            let bundleID = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !bundleID.isEmpty, let rule = AppTilingRule(rawValue: popup.titleOfSelectedItem ?? "") else { continue }
            rules[bundleID] = rule
        }
        settings.appRules = rules

        guard settings.save() else {
            statusLabel.stringValue = "Write failed — check permissions."
            return
        }
        statusLabel.stringValue = "Saved — daemon reloaded."
        daemonControl.send("reload")
    }
}