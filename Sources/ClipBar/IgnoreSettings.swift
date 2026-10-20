import AppKit
import UniformTypeIdentifiers

@MainActor
final class IgnoreSettingsViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    private enum Mode: Int { case apps, types, regex }

    private var mode = Mode.apps
    private var items: [String] = []

    private let modeControl = NSSegmentedControl(
        labels: ["Applications", "Pasteboard types", "Regex"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let table = NSTableView()
    private let help = NSTextField(wrappingLabelWithString: "")
    private let resetButton = NSButton(title: "Reset to defaults", target: nil, action: nil)

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Ignore"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        view = root
        preferredContentSize = NSSize(width: 520, height: 360)

        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged)

        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 440).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 190).isActive = true

        let add = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!,
            target: self, action: #selector(addTapped))
        let remove = NSButton(
            image: NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!,
            target: self, action: #selector(removeTapped))
        for b in [add, remove] { b.bezelStyle = .smallSquare }
        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        resetButton.controlSize = .small
        let buttons = NSStackView(views: [add, remove, UI.spacer(), resetButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 4
        UI.fixedWidth(buttons, 440)

        help.font = .systemFont(ofSize: 11)
        help.textColor = .tertiaryLabelColor
        help.preferredMaxLayoutWidth = 440
        UI.fixedWidth(help, 440)

        let stack = NSStackView(views: [modeControl, scroll, buttons, help])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        setMode(Mode(rawValue: modeControl.selectedSegment) ?? .apps)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        view.window?.makeFirstResponder(nil)  // finish any edit in progress
        items.removeAll { $0.isEmpty }
        save()
    }

    // MARK: Mode

    private func setMode(_ m: Mode) {
        mode = m
        switch m {
        case .apps: items = Settings.ignoredApps
        case .types: items = Settings.ignoredTypes
        case .regex: items = Settings.ignoredRegex
        }

        for c in table.tableColumns { table.removeTableColumn(c) }
        switch m {
        case .apps:
            addColumn("name", "Application", 170, editable: false)
            addColumn("value", "Bundle ID", 270, editable: true)
            help.stringValue = "Copies made in these apps are never stored. Click + to pick an app."
        case .types:
            addColumn("value", "Pasteboard type", 440, editable: true)
            help.stringValue =
                "Copies carrying any of these types are never stored. Password managers use them to mark secrets."
        case .regex:
            addColumn("value", "Regular expression", 440, editable: true)
            help.stringValue =
                "Text copies matching any of these are never stored, for example ^[A-Za-z0-9]{32}$ to skip tokens."
        }
        resetButton.isHidden = m != .types
        table.reloadData()
    }

    private func addColumn(_ id: String, _ title: String, _ width: CGFloat, editable: Bool) {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        c.title = title
        c.width = width
        c.isEditable = editable
        (c.dataCell as? NSTextFieldCell)?.lineBreakMode = .byTruncatingTail
        table.addTableColumn(c)
    }

    private func save() {
        let clean = items.filter { !$0.isEmpty }
        switch mode {
        case .apps: Settings.ignoredApps = clean
        case .types: Settings.ignoredTypes = clean
        case .regex: Settings.ignoredRegex = clean
        }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int)
        -> Any?
    {
        guard row < items.count else { return nil }
        if mode == .apps, tableColumn?.identifier.rawValue == "name" { return appName(items[row]) }
        return items[row]
    }

    func tableView(
        _ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?,
        row: Int
    ) {
        guard row < items.count else { return }
        let s = (object as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            items.remove(at: row)  // clearing a row deletes it
        } else if mode == .regex, (try? NSRegularExpression(pattern: s)) == nil {
            NSSound.beep()  // invalid pattern: keep the old value
            if items[row].isEmpty { items.remove(at: row) }
        } else {
            items[row] = s
        }
        save()
        table.reloadData()
    }

    // MARK: Actions

    @objc private func modeChanged() {
        view.window?.makeFirstResponder(nil)
        items.removeAll { $0.isEmpty }
        save()
        setMode(Mode(rawValue: modeControl.selectedSegment) ?? .apps)
    }

    @objc private func addTapped() {
        if mode == .apps {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = true
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.prompt = "Ignore"
            guard panel.runModal() == .OK else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier, !items.contains(id) {
                    items.append(id)
                }
            }
            save()
            table.reloadData()
        } else {
            items.append("")
            table.reloadData()
            table.selectRowIndexes([items.count - 1], byExtendingSelection: false)
            table.editColumn(0, row: items.count - 1, with: nil, select: true)
        }
    }

    @objc private func removeTapped() {
        let rows = table.selectedRowIndexes
        guard !rows.isEmpty else { return }
        for r in rows.reversed() where r < items.count { items.remove(at: r) }
        save()
        table.reloadData()
    }

    @objc private func resetTapped() {
        items = Settings.defaultIgnoredTypes
        save()
        table.reloadData()
    }
}
