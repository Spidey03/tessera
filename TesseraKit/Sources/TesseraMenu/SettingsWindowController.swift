import AppKit
import TesseraUI
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
    private var appPicker: AppPickerWindowController?

    /// Root column of the settings window. Kept as a property because
    /// NSVisualEffectView does not derive its `fittingSize` from subviews, so
    /// the window is sized from this stack (see `padWindowHeight()`).
    private let rootStack = NSStackView()

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
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 640),
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
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false

        let root = rootStack
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: effect.topAnchor),
            root.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        let title = NSTextField(labelWithString: "Tessera")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Tile your windows — changes apply on Save.")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        let headerText = NSStackView(views: [title, subtitle])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 2
        let header = NSStackView(views: [NSImageView(image: TesseraMenuIcon.settingsHeaderImage()), headerText])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY
        root.addArrangedSubview(header)
        root.setCustomSpacing(18, after: header)

        root.addArrangedSubview(sectionHeader("Tiling"))

        root.addArrangedSubview(fieldRow("Gap between windows (px):", gapSizeField))
        let outerGapRow = fieldRow("Outer gap (px):", outerGapField)
        root.addArrangedSubview(outerGapRow)
        root.setCustomSpacing(10, after: outerGapRow)

        newWindowFocusCheck.target = self
        let focusRow = checkboxRow(newWindowFocusCheck)
        root.addArrangedSubview(focusRow)
        root.setCustomSpacing(18, after: focusRow)

        root.addArrangedSubview(sectionHeader("Animation"))

        animationEnabledCheck.target = self
        root.addArrangedSubview(checkboxRow(animationEnabledCheck))
        root.addArrangedSubview(fieldRow("Steps:", animationStepsField))
        let durationRow = fieldRow("Duration (s):", animationDurationField)
        root.addArrangedSubview(durationRow)
        root.setCustomSpacing(18, after: durationRow)

        root.addArrangedSubview(sectionHeader("Per-app tiling rules"))

        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 6
        rulesStack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 6, right: 6)
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
            // 4 rows at the fixed 22 pt row height + 6 pt spacing, plus the
            // stack's 4/6 pt insets — an exact multiple of the row pitch, so
            // the list never rests on a half-drawn row.
            scroll.heightAnchor.constraint(equalToConstant: 122),
            scroll.widthAnchor.constraint(equalToConstant: 428),
        ])
        root.addArrangedSubview(scroll)

        let addButton = NSButton(title: "+ Add Rule", target: self, action: #selector(addRule))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .small
        let rowButtons = NSStackView(views: [addButton])
        rowButtons.orientation = .horizontal
        rowButtons.spacing = 8
        root.addArrangedSubview(rowButtons)
        root.setCustomSpacing(18, after: rowButtons)

        root.addArrangedSubview(sectionHeader("Hotkeys"))

        hotkeyStack.orientation = .vertical
        hotkeyStack.alignment = .leading
        hotkeyStack.spacing = 4
        hotkeyStack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 6, right: 6)
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
            // 9 rows at the fixed 20 pt row height + 4 pt spacing, plus insets.
            hotkeyScroll.heightAnchor.constraint(equalToConstant: 226),
            hotkeyScroll.widthAnchor.constraint(equalToConstant: 428),
        ])
        root.addArrangedSubview(hotkeyScroll)
        root.setCustomSpacing(14, after: hotkeyScroll)

        let saveButton = NSButton(title: "Save & Reload", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        let bottom = NSStackView(views: [saveButton, statusLabel])
        bottom.orientation = .horizontal
        bottom.spacing = 12
        bottom.alignment = .centerY
        root.addArrangedSubview(bottom)

        return effect
    }

    /// Rounded capsule behind a section title.
    private func sectionHeader(_ text: String) -> NSView {
        SectionChip(title: text)
    }

    /// A right-aligned control row (macOS settings style): label left, rounded
    /// input pinned to the content column's right edge.
    private func fieldRow(_ text: String, _ field: NSTextField, width: CGFloat = 120) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let input = RoundedTextInput(wrapping: field,
                                     font: .monospacedDigitSystemFont(ofSize: 13, weight: .regular))
        input.widthAnchor.constraint(equalToConstant: width).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, input])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 428).isActive = true
        return row
    }

    /// A full-width checkbox row so its label sits at the left column edge.
    private func checkboxRow(_ check: NSButton) -> NSView {
        check.font = NSFont.systemFont(ofSize: 13)
        check.translatesAutoresizingMaskIntoConstraints = false
        check.widthAnchor.constraint(equalToConstant: 428).isActive = true
        return check
    }

    /// Grow the window to fit content after building (auto layout has no fixed height).
    private func padWindowHeight() {
        window?.layoutIfNeeded()
        let fitting = rootStack.fittingSize
        window?.setContentSize(NSSize(width: max(468, fitting.width), height: fitting.height + 4))
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
        for subview in hotkeyStack.arrangedSubviews {
            hotkeyStack.removeArrangedSubview(subview)
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
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 20).isActive = true
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
        if names.isEmpty {
            statusLabel.stringValue = "Hotkeys need a modifier (Cmd, Opt, Ctrl or Shift)."
            cancelHotkeyRecording()
            return
        }
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
        let input = RoundedTextInput(wrapping: field)
        input.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let popup = NSPopUpButton()
        for r in allRules {
            popup.addItem(withTitle: r.rawValue)
        }
        popup.selectItem(withTitle: rule.rawValue)
        popup.controlSize = .small

        let removeButton = NSButton(title: "–", target: self, action: #selector(removeRule))
        removeButton.bezelStyle = .rounded
        removeButton.tag = ruleRows.count

        let row = NSStackView(views: [input, popup, removeButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true
        rulesStack.addArrangedSubview(row)
        ruleRows.append((field: field, popup: popup))
        for i in 0..<ruleRows.count {
            if let button = rulesStack.arrangedSubviews[i].subviews.compactMap({ $0 as? NSButton }).first {
                button.tag = i
            }
        }
    }

    @objc private func addRule() {
        guard let parent = window else { return }
        if appPicker == nil {
            let picker = AppPickerWindowController()
            picker.onPick = { [weak self] app in
                self?.addRuleRow(bundleID: app.bundleID, rule: .normal)
            }
            appPicker = picker
        }
        appPicker?.present(in: parent)
    }

    @objc private func removeRule(_ sender: NSButton) {
        guard ruleRows.indices.contains(sender.tag) else { return }
        let removed = rulesStack.arrangedSubviews[sender.tag]
        ruleRows.remove(at: sender.tag)
        rulesStack.removeArrangedSubview(removed)
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