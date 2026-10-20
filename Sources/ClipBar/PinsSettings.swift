import AppKit

@MainActor
final class PinsSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate
{
    /// Keys the panel already uses with ⌘ (or the menu): copy/paste/select-all/cut/undo, pin, quit.
    static let reserved: Set<String> = ["a", "c", "v", "x", "z", "p", "q"]

    private let store: ClipStore
    private var pins: [Clip] = []
    private let table = NSTableView()
    private let help = NSTextField(wrappingLabelWithString: "")

    init(store: ClipStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        title = "Pins"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        view = root
        preferredContentSize = NSSize(width: 520, height: 360)

        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        addColumn("title", "Title", 140, editable: true)
        addColumn("key", "Key", 50, editable: true)
        addColumn("item", "Item", 250, editable: false)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 460).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let remove = NSButton(
            image: NSImage(systemSymbolName: "pin.slash", accessibilityDescription: "Unpin")!,
            target: self, action: #selector(unpinTapped))
        remove.bezelStyle = .smallSquare
        remove.toolTip = "Unpin selected"
        let buttons = NSStackView(views: [remove, UI.spacer()])
        buttons.orientation = .horizontal
        UI.fixedWidth(buttons, 460)

        help.stringValue =
            "Double-click a title or key to edit. A pinned item shows its title in the list, and ⌘ plus its key chooses it. Keys are single letters; A C V X Z P Q are taken."
        help.font = .systemFont(ofSize: 11)
        help.textColor = .tertiaryLabelColor
        help.preferredMaxLayoutWidth = 460
        UI.fixedWidth(help, 460)

        let stack = NSStackView(views: [scroll, buttons, help])
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
        reload()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        view.window?.makeFirstResponder(nil)  // finish any edit in progress
    }

    private func addColumn(_ id: String, _ title: String, _ width: CGFloat, editable: Bool) {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        c.title = title
        c.width = width
        c.isEditable = editable
        (c.dataCell as? NSTextFieldCell)?.lineBreakMode = .byTruncatingTail
        table.addTableColumn(c)
    }

    private func reload() {
        pins = store.pins()
        table.reloadData()
    }

    private func describe(_ clip: Clip) -> String {
        switch clip.kind {
        case .image: return "Image \(clip.width)×\(clip.height)"
        case .text, .file: return Formats.rowText(clip.preview)
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { pins.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int)
        -> Any?
    {
        guard row < pins.count else { return nil }
        switch tableColumn?.identifier.rawValue {
        case "title": return pins[row].title
        case "key": return pins[row].pinKey.uppercased()
        default: return describe(pins[row])
        }
    }

    func tableView(
        _ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?,
        row: Int
    ) {
        guard row < pins.count else { return }
        let id = pins[row].id
        let s = (object as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch tableColumn?.identifier.rawValue {
        case "title":
            store.setPinTitle(id, s)
        case "key":
            let key = s.lowercased()
            if key.isEmpty {
                store.setPinKey(id, "")
            } else if key.count == 1, let ch = key.first, ch.isLetter, ch.isASCII,
                !Self.reserved.contains(key)
            {
                store.setPinKey(id, key)
            } else {
                NSSound.beep()  // not a free single letter: keep the old key
            }
        default: break
        }
        reload()
    }

    // MARK: Actions

    @objc private func unpinTapped() {
        let rows = table.selectedRowIndexes
        guard !rows.isEmpty else { return }
        for r in rows where r < pins.count { store.togglePin(pins[r].id) }
        reload()
    }
}
