import AppKit
import ServiceManagement

@MainActor
final class GeneralSettingsViewController: NSViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        title = "General"
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }
    private let launchCheck = NSButton(
        checkboxWithTitle: "Launch ClipBar at login", target: nil, action: nil)
    private let searchPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let searchHelp = NSTextField(wrappingLabelWithString: "")
    private let confirmCheck = NSButton(
        checkboxWithTitle: "Ask before clearing history", target: nil, action: nil)
    private let quitCheck = NSButton(
        checkboxWithTitle: "Clear history on quit", target: nil, action: nil)

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        view = root
        preferredContentSize = NSSize(width: 520, height: 360)

        launchCheck.target = self
        launchCheck.action = #selector(launchToggled)
        confirmCheck.target = self
        confirmCheck.action = #selector(confirmToggled)
        quitCheck.target = self
        quitCheck.action = #selector(quitToggled)

        searchPopup.addItems(withTitles: SearchMode.allCases.map(\.title))
        searchPopup.target = self
        searchPopup.action = #selector(searchChanged)

        let grid = NSGridView(
            views: [
                [heading("Startup:"), launchCheck],
                [heading("Search:"), searchPopup],
                [NSGridCell.emptyContentView, note(searchHelp)],
                [heading("History:"), confirmCheck],
                [NSGridCell.emptyContentView, quitCheck],
                [
                    NSGridCell.emptyContentView,
                    note(NSTextField(wrappingLabelWithString: "Pinned items are always kept.")),
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
        // The system is the source of truth for login items (the user can change it in System Settings).
        launchCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        searchPopup.selectItem(at: SearchMode.allCases.firstIndex(of: Settings.searchMode) ?? 0)
        searchHelp.stringValue = Settings.searchMode.help
        confirmCheck.state = Settings.confirmClear ? .on : .off
        quitCheck.state = Settings.clearOnQuit ? .on : .off
    }

    // MARK: Helpers

    private func heading(_ s: String) -> NSTextField {
        UI.label(s, size: 13, color: .secondaryLabelColor)
    }

    private func note(_ t: NSTextField) -> NSTextField {
        t.font = .systemFont(ofSize: 11)
        t.textColor = .tertiaryLabelColor
        t.preferredMaxLayoutWidth = 280
        return UI.fixedWidth(t, 280)
    }

    // MARK: Actions

    @objc private func launchToggled(_ sender: NSButton) {
        let want = sender.state == .on
        do {
            if want {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        if want, SMAppService.mainApp.status == .requiresApproval {
            let alert = NSAlert()
            alert.messageText = "Approval needed"
            alert.informativeText = "Allow ClipBar in System Settings > General > Login Items."
            alert.runModal()
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func searchChanged() {
        let i = max(searchPopup.indexOfSelectedItem, 0)
        Settings.searchMode = SearchMode.allCases[i]
        searchHelp.stringValue = Settings.searchMode.help
    }

    @objc private func confirmToggled(_ sender: NSButton) {
        Settings.confirmClear = sender.state == .on
    }
    @objc private func quitToggled(_ sender: NSButton) {
        Settings.clearOnQuit = sender.state == .on
    }
}
