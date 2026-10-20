import AppKit

@MainActor
final class AppearanceSettingsViewController: NSViewController {
    private let symbolsCheck = NSButton(
        checkboxWithTitle: "Show special symbols", target: nil, action: nil)

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

        let help = NSTextField(
            wrappingLabelWithString:
                "Shows ⏎ for new lines, ⇥ for tabs and · for spaces at the start or end of an item. Applies to items copied from now on."
        )
        help.font = .systemFont(ofSize: 11)
        help.textColor = .tertiaryLabelColor
        help.preferredMaxLayoutWidth = 300
        UI.fixedWidth(help, 300)

        let grid = NSGridView(
            views: [
                [UI.label("List:", size: 13, color: .secondaryLabelColor), symbolsCheck],
                [NSGridCell.emptyContentView, help],
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
    }

    @objc private func symbolsToggled(_ sender: NSButton) {
        Settings.showSpecialSymbols = sender.state == .on
    }
}
