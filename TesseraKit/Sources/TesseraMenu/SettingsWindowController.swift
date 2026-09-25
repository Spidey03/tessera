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

    private let hotkeyStack = NSStackView()
    private struct HotkeyRow {
        let action: String
        let comboButton: NSButton
        let resetButton: NSButton
    }
    private var hotkeyRows: [HotkeyRow] = []
    private var hotkeyMonitor: Any?
    private var recordingAction: String?

    private let statusLabel = NSTextField(labelWithString: "")

    private let allRules: [AppTilingRule] = [.normal, .ignore, .float, .sticky]

    private let hotkeyTitles: [String: String] = [
        "tile": "Tile all windows",
        "focusLeft": "Focus left / previous",
        "focusRight": "Focus right / next",
        "focusUp": "Focus up",
        "focusDown": "Focus down",
        "cycleNext": "Cycle next window",
        "cyclePrev": "Cycle previous window",
        "remove": "Remove focused window",
        "fullscreen": "Toggle fullscreen",
        "toggleSplit": "Toggle split direction",
        "resizeShrink": "Resize split — shrink",
        "resizeGrow": "Resize split — grow",
        "cycleLayout": "Cycle layout",
        "quit": "Quit daemon",
    ]

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

    func windowWillClose(_ notification: Notification) {
        cancelHotkeyRecording()
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

        root.addArrangedSubview(sectionLabel("Hotkeys"))

        hotkeyStack.orientation = .vertical
        hotkeyStack.alignment = .leading
        hotkeyStack.spacing = 4
        hotkeyStack.translatesAutoresizingMaskIntoConstraints = false
        let hotkeyScroll = NSScrollView()
        hotkeyScroll.documentView = hotkeyStack
        hotkeyScroll.hasVerticalScroller = true
        hotkeyScroll.hasHorizontalScroller = false
        hotkeyScroll.borderType = .bezelBorder
        NSLayoutConstraint.activate([
            hotkeyStack.leadingAnchor.constraint(equalTo: hotkeyScroll.contentView.leadingAnchor),
            hotkeyStack.topAnchor.constraint(equalTo: hotkeyScroll.contentView.topAnchor),
            hotkeyStack.widthAnchor.constraint(equalTo: hotkeyScroll.contentView.widthAnchor),
            hotkeyScroll.heightAnchor.constraint(equalToConstant: 220),
            hotkeyScroll.widthAnchor.constraint(equalToConstant: 428),
        ])
        root.addArrangedSubview(hotkeyScroll)

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
        rebuildHotkeyRows()
        statusLabel.stringValue = ""
    }

    // MARK: - Hotkeys

    private func mergedHotkeys() -> [HotkeyBinding] {
        HotkeyBindings.merge(defaults: HotkeyBindings.defaults, overrides: settings.hotkeys)
    }

    private func effectiveCombo(for action: String) -> String {
        let combos = HotkeyBindings.activeCombos(mergedHotkeys(), action: action)
        return combos.isEmpty ? "—" : combos.joined(separator: ", ")
    }

    private func rebuildHotkeyRows() {
        for row in hotkeyRows {
            hotkeyStack.removeArrangedSubview(row.comboButton)
            hotkeyStack.removeArrangedSubview(row.resetButton)
            for view in [row.comboButton, row.resetButton] {
                view.removeFromSuperview()
            }
        }
        hotkeyRows = []
        cancelHotkeyRecording()
        for action in HotkeyBindings.canonicalActions {
            let title = NSTextField(labelWithString: hotkeyTitles[action] ?? action)
            title.font = NSFont.systemFont(ofSize: 12)
            title.widthAnchor.constraint(equalToConstant: 190).isActive = true

            let comboButton = NSButton(title: effectiveCombo(for: action), target: self,
                                       action: #selector(recordHotkey))
            comboButton.bezelStyle = .rounded
            comboButton.controlSize = .small
            comboButton.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            comboButton.widthAnchor.constraint(equalToConstant: 150).isActive = true

            let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetHotkey))
            resetButton.bezelStyle = .inline
            resetButton.controlSize = .small
            resetButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
            resetButton.isHidden = settings.hotkeys[action] == nil

            let row = NSStackView(views: [title, comboButton, resetButton])
            row.orientation = .horizontal
            row.spacing = 8
            hotkeyStack.addArrangedSubview(row)
            hotkeyRows.append(HotkeyRow(action: action, comboButton: comboButton, resetButton: resetButton))
        }
    }

    private func refreshHotkeyRow(_ row: HotkeyRow) {
        row.comboButton.title = effectiveCombo(for: row.action)
        row.resetButton.isHidden = settings.hotkeys[row.action] == nil
    }

    @objc private func recordHotkey(_ sender: NSButton) {
        guard let row = hotkeyRows.first(where: { $0.comboButton === sender }),
              recordingAction == nil else { return }
        recordingAction = row.action
        sender.title = "Press new keys…"
        statusLabel.stringValue = "Press a key combination (Esc cancels)."
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.recordingAction != nil else { return event }
            if event.keyCode == 53 { // Esc
                self.cancelHotkeyRecording()
                return nil
            }
            self.commitHotkey(event)
            return nil
        }
    }

    private func commitHotkey(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        let names = flagNames(from: event.modifierFlags)
        let spec = HotkeySpec(keyCode: UInt16(event.keyCode), flags: names)

        let conflict = mergedHotkeys().first { binding in
            binding.action != action
                && binding.keyCode == spec.keyCode
                && BindingFlagsEqual(binding.flags, HotkeyBindings.normalizedFlags(names))
        }
        if let conflict {
            statusLabel.stringValue = "\(conflict.action) already uses \(conflict.display)."
            cancelHotkeyRecording()
            return
        }

        settings.hotkeys[action] = spec
        cancelHotkeyRecording()
        if let row = hotkeyRows.first(where: { $0.action == action }) {
            refreshHotkeyRow(row)
        }
        statusLabel.stringValue = ""
    }

    private func flagNames(from flags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.command) { names.append("cmd") }
        if flags.contains(.option) { names.append("opt") }
        if flags.contains(.control) { names.append("ctrl") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.function) { names.append("fn") }
        if flags.contains(.capsLock) { names.append("caps") }
        return names
    }

    private func BindingFlagsEqual(_ a: [String], _ b: [String]) -> Bool {
        Set(a) == Set(b)
    }

    @objc private func resetHotkey(_ sender: NSButton) {
        guard let row = hotkeyRows.first(where: { $0.resetButton === sender }) else { return }
        settings.hotkeys[row.action] = nil
        refreshHotkeyRow(row)
    }

    private func cancelHotkeyRecording() {
        recordingAction = nil
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hotkeyMonitor = nil
        for row in hotkeyRows {
            row.comboButton.title = effectiveCombo(for: row.action)
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