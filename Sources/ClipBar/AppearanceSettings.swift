import AppKit

@MainActor
final class AppearanceSettingsViewController: NSViewController {
    private let symbolsCheck = NSButton(
        checkboxWithTitle: "Show special symbols", target: nil, action: nil)
    private let hexCheck = NSButton(
        checkboxWithTitle: "Show hex color swatch", target: nil, action: nil)

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Appearance"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        view = root
        preferredContentSize = NSSize(width: 520, height: 360)

        symbolsCheck.target = self
        symbolsCheck.action = #selector(symbolsToggled)
        hexCheck.target = self
        hexCheck.action = #selector(hexToggled)

        let grid = NSGridView(
            views: [
                [UI.label("List:", size: 13, color: .secondaryLabelColor), symbolsCheck],
                [
                    NSGridCell.emptyContentView,
                    note(
                        "Shows ⏎ for new lines, ⇥ for tabs and · for spaces at the start or end of an item. Applies to items copied from now on."
                    ),
                ],
                [UI.label("Colors:", size: 13, color: .secondaryLabelColor), hexCheck],
                [
                    NSGridCell.emptyContentView,
                    note(
                        "A dot in the list and a large swatch in the preview for items like #FF5733, #F00 or #FF5733CC."
                    ),
                ],
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
        symbolsCheck.state = Settings.showSpecialSymbols ? .on : .off
        hexCheck.state = Settings.showHexSwatch ? .on : .off
    }

    private func note(_ s: String) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: 11)
        t.textColor = .tertiaryLabelColor
        t.preferredMaxLayoutWidth = 300
        return UI.fixedWidth(t, 300)
    }

    @objc private func symbolsToggled(_ sender: NSButton) {
        Settings.showSpecialSymbols = sender.state == .on
    }
    @objc private func hexToggled(_ sender: NSButton) {
        Settings.showHexSwatch = sender.state == .on
    }
}
