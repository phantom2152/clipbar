import AppKit

@MainActor
final class StorageSettingsViewController: NSViewController {
    private let store: ClipStore

    private let itemsField = NSTextField()
    private let itemsStepper = NSStepper()
    private let sizeField = NSTextField()
    private let sizeStepper = NSStepper()
    private let textCheck = NSButton(checkboxWithTitle: "Text", target: nil, action: nil)
    private let imageCheck = NSButton(checkboxWithTitle: "Images", target: nil, action: nil)
    private let filesCheck = NSButton(
        checkboxWithTitle: "Files and folders", target: nil, action: nil)
    private let usage = UI.label("", size: 13, color: .secondaryLabelColor)

    private let itemsRange = 10...5000
    private let sizeRange = 0...100_000

    init(store: ClipStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
        title = "Storage"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        view = root
        preferredContentSize = NSSize(width: 520, height: 360)

        setup(
            itemsField, itemsStepper, range: itemsRange, step: 10,
            field: #selector(itemsEdited), stepper: #selector(itemsStepped))
        setup(
            sizeField, sizeStepper, range: sizeRange, step: 50,
            field: #selector(sizeEdited), stepper: #selector(sizeStepped))

        for (check, action) in [
            (textCheck, #selector(textToggled)),
            (imageCheck, #selector(imageToggled)),
            (filesCheck, #selector(filesToggled)),
        ] {
            check.target = self
            check.action = action
        }

        let grid = NSGridView(
            views: [
                [heading("Keep:"), numberRow(itemsField, itemsStepper, "items")],
                [heading("Size limit:"), numberRow(sizeField, sizeStepper, "MB  (0 = no limit)")],
                [
                    NSGridCell.emptyContentView,
                    note(
                        "The oldest unpinned items are removed first. Pinned items are never removed. Size is approximate."
                    ),
                ],
                [heading("Store:"), textCheck],
                [NSGridCell.emptyContentView, imageCheck],
                [NSGridCell.emptyContentView, filesCheck],
                [
                    NSGridCell.emptyContentView,
                    note("Unticked kinds are ignored when copied. Items already stored are kept."),
                ],
                [heading("Using:"), usage],
            ] as [[NSView]])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            grid.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        itemsField.integerValue = Settings.maxItems
        itemsStepper.integerValue = Settings.maxItems
        sizeField.integerValue = Settings.maxSizeMB
        sizeStepper.integerValue = Settings.maxSizeMB
        textCheck.state = Settings.storeText ? .on : .off
        imageCheck.state = Settings.storeImages ? .on : .off
        filesCheck.state = Settings.storeFiles ? .on : .off
        refreshUsage()
    }

    // MARK: Helpers

    private func heading(_ s: String) -> NSTextField {
        UI.label(s, size: 13, color: .secondaryLabelColor)
    }

    private func note(_ s: String) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: 11)
        t.textColor = .tertiaryLabelColor
        t.preferredMaxLayoutWidth = 300
        return UI.fixedWidth(t, 300)
    }

    private func setup(
        _ field: NSTextField, _ stepper: NSStepper, range: ClosedRange<Int>, step: Double,
        field fieldAction: Selector, stepper stepperAction: Selector
    ) {
        let nf = NumberFormatter()
        nf.numberStyle = .none
        nf.allowsFloats = false
        field.formatter = nf
        field.alignment = .right
        field.target = self
        field.action = fieldAction
        UI.fixedWidth(field, 70)

        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = step
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = stepperAction
    }

    private func numberRow(_ field: NSTextField, _ stepper: NSStepper, _ unit: String) -> NSView {
        let label = UI.label(unit, size: 13, color: .secondaryLabelColor)
        let row = NSStackView(views: [field, stepper, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func refreshUsage() {
        usage.stringValue = "\(Formats.bytes(store.usedBytes())) in \(store.totalCount()) items"
    }

    private func setItems(_ v: Int) {
        let n = min(max(v, itemsRange.lowerBound), itemsRange.upperBound)
        Settings.maxItems = n
        itemsField.integerValue = n
        itemsStepper.integerValue = n
        store.applyLimits()
        refreshUsage()
    }

    private func setSize(_ v: Int) {
        let n = min(max(v, sizeRange.lowerBound), sizeRange.upperBound)
        Settings.maxSizeMB = n
        sizeField.integerValue = n
        sizeStepper.integerValue = n
        store.applyLimits()
        refreshUsage()
    }

    // MARK: Actions

    @objc private func itemsEdited() { setItems(itemsField.integerValue) }
    @objc private func itemsStepped() { setItems(itemsStepper.integerValue) }
    @objc private func sizeEdited() { setSize(sizeField.integerValue) }
    @objc private func sizeStepped() { setSize(sizeStepper.integerValue) }
    @objc private func textToggled(_ s: NSButton) { Settings.storeText = s.state == .on }
    @objc private func imageToggled(_ s: NSButton) { Settings.storeImages = s.state == .on }
    @objc private func filesToggled(_ s: NSButton) { Settings.storeFiles = s.state == .on }
}
