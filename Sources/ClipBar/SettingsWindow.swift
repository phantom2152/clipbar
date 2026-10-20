import AppKit

/// Normal window (not part of the menu bar popup) with a toolbar of tabs.
@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        let pages: [(title: String, symbol: String)] = [
            ("General", "gearshape"),
            ("Storage", "externaldrive"),
            ("Pins", "pin"),
            ("Ignore", "nosign"),
            ("Appearance", "paintbrush"),
            ("Advanced", "slider.horizontal.3"),
        ]
        for page in pages {
            let vc: NSViewController
            switch page.title {
            case "General": vc = GeneralSettingsViewController()
            case "Appearance": vc = AppearanceSettingsViewController()
            default: vc = SettingsPageViewController(title: page.title)
            }
            let item = NSTabViewItem(viewController: vc)
            item.label = page.title
            item.image = NSImage(
                systemSymbolName: page.symbol, accessibilityDescription: page.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "General"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// One tab's content. Placeholder for now; each later step fills one of these in.
@MainActor
final class SettingsPageViewController: NSViewController {
    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        let label = UI.label(
            "\(title ?? "") settings are coming soon.", size: 13, color: .secondaryLabelColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
        preferredContentSize = NSSize(width: 520, height: 360)
    }
}