import AppKit

/// A macOS `.app` bundle discovered on disk, as offered by the rule picker.
struct InstalledApp: Hashable {
    let name: String
    let bundleID: String
    let url: URL
}

/// Scans the standard application folders for installed apps.
///
/// Uses `Bundle` (no private LaunchServices API) and skips package descendants
/// so helper apps nested inside e.g. Xcode.app are not offered.
enum AppCatalog {
    static var searchRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
        ]
    }

    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var byBundleID: [String: InstalledApp] = [:]

        for root in searchRoots where fm.fileExists(atPath: root.path) {
            guard let walker = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in walker where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                guard byBundleID[id] == nil else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                byBundleID[id] = InstalledApp(name: name, bundleID: id, url: url)
            }
        }

        return byBundleID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

/// Sheet for picking an installed app when adding a per-app tiling rule:
/// a rounded search field over a two-column list (app name + bundle id).
@MainActor
final class AppPickerWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    /// Called with the chosen app (or a raw bundle id typed by the user).
    var onPick: ((InstalledApp) -> Void)?

    private let search = RoundedSearchInput(placeholder: "Search apps or bundle identifiers")
    private let table = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No matching apps")
    private let addButton = NSButton(title: "Add Rule", target: nil, action: nil)
    private weak var parent: NSWindow?

    private var apps: [InstalledApp] = []
    private var matches: [InstalledApp] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Rule"
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContentView()
        search.searchField.delegate = self
        apps = AppCatalog.installedApps()
        refilter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(in parent: NSWindow) {
        guard let sheet = window else { return }
        self.parent = parent
        search.searchField.stringValue = ""
        refilter()
        parent.beginSheet(sheet) { [weak self] _ in
            self?.parent = nil
        }
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "App"
        nameColumn.width = 170
        let idColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bundleID"))
        idColumn.title = "Bundle Identifier"
        idColumn.width = 240
        table.addTableColumn(nameColumn)
        table.addTableColumn(idColumn)
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.style = .fullWidth
        table.target = self
        table.doubleAction = #selector(confirm)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true

        let tableBox = RoundedBox()
        tableBox.cornerRadius = 8
        tableBox.contentInsets = NSEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        tableBox.translatesAutoresizingMaskIntoConstraints = false
        tableBox.setContent(scroll)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        addButton.target = self
        addButton.action = #selector(confirm)
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.isEnabled = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\r"
        cancelButton.keyEquivalentModifierMask = [.command]

        let footer = NSStackView(views: [addButton, cancelButton])
        footer.orientation = .horizontal
        footer.spacing = 8

        let root = NSStackView(views: [search, tableBox, emptyLabel, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.insertView(spacer, at: 0, in: .leading)

        search.widthAnchor.constraint(equalToConstant: 428).isActive = true
        tableBox.widthAnchor.constraint(equalToConstant: 428).isActive = true
        emptyLabel.widthAnchor.constraint(equalToConstant: 428).isActive = true

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: wrapper.topAnchor),
            root.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        effect.addSubview(wrapper)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        effect.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrapper.topAnchor.constraint(equalTo: effect.topAnchor),
            wrapper.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            wrapper.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            wrapper.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    // MARK: - Filtering

    private func refilter() {
        let query = search.searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            matches = apps
        } else {
            matches = apps.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.bundleID.localizedCaseInsensitiveContains(query)
            }
        }
        table.reloadData()
        if !matches.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
        emptyLabel.isHidden = !matches.isEmpty
        updateAddButton()
    }

    private func typedBundleID() -> String? {
        let text = search.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // "com.example.app" style input: honour it verbatim even without a match.
        guard !text.isEmpty, text.contains("."), !text.contains(" ") else { return nil }
        return text
    }

    private func updateAddButton() {
        addButton.isEnabled = table.selectedRow >= 0 || typedBundleID() != nil
    }

    private func selection() -> InstalledApp? {
        let row = table.selectedRow
        guard matches.indices.contains(row) else { return nil }
        return matches[row]
    }

    // MARK: - Actions

    @objc private func confirm() {
        if let app = selection() {
            finish(with: app)
        } else if let typed = typedBundleID() {
            finish(with: InstalledApp(name: typed, bundleID: typed,
                                       url: URL(fileURLWithPath: "/Applications/\(typed).app")))
        }
    }

    private func finish(with app: InstalledApp) {
        onPick?(app)
        close()
    }

    @objc private func cancel() {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        if let parent, let sheet = window {
            parent.endSheet(sheet)
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        matches.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard matches.indices.contains(row) else { return nil }
        let app = matches[row]
        return tableColumn?.identifier.rawValue == "name" ? app.name : app.bundleID
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateAddButton()
    }
}

extension AppPickerWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        refilter()
    }
}
