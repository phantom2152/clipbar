import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let quitMenu = NSMenu()
    private let store = ClipStore()
    private var panel: PanelViewController!
    private lazy var settings = SettingsWindowController()

    private var signalSources: [DispatchSourceSignal] = []
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var autoCloseSuspended = false  // true while an alert is up

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar icon: left click toggles the panel, right click shows a tiny Quit menu
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked)
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let image = Symbols.image("doc.on.clipboard", size: 15, weight: .regular)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ClipBar"
        }
        quitMenu.addItem(
            NSMenuItem(
                title: "Quit ClipBar", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))

        store.sweepOrphans()
        store.monitor.start()

        panel = PanelViewController(store: store)
        panel.onClose = { [weak self] in self?.closePopover() }
        panel.onQuit = { NSApp.terminate(nil) }
        panel.onModalBusy = { [weak self] busy in self?.autoCloseSuspended = busy }
        store.onChange = { [weak self] in self?.panel.storeChanged() }
        _ = panel.view
        panel.onSettings = { [weak self] in
            self?.closePopover()  // the popup goes away, then the normal window opens
            self?.settings.show()
        }

        // pkill / Ctrl+C take the normal quit path
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { Task { @MainActor in NSApp.terminate(nil) } }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Panel open / close

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            item.menu = quitMenu
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        if panel.isShown { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = item.button else { return }
        panel.prepareForOpen()
        NSApp.activate(ignoringOtherApps: true)
        panel.show(below: button)
        panel.focusSearch()

        // A click in ANOTHER app closes the panel (clicks inside our own windows never reach this)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.autoCloseSuspended else { return }
                // A click on our own menu bar icon is handled by statusClicked (toggle), not here.
                if let b = self.item.button, let w = b.window,
                    w.convertToScreen(b.convert(b.bounds, to: nil)).contains(NSEvent.mouseLocation)
                {
                    return
                }
                self.closePopover()
            }
        }
        // Esc closes; arrows / Return / ⌘1-9 / ⌘P / ⌘⌫ go to the panel (ignored while an alert is up)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] (event: NSEvent) -> NSEvent? in
            let code = event.keyCode
            let flags = event.modifierFlags
            let chars = event.charactersIgnoringModifiers ?? ""
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isShown, !self.autoCloseSuspended else { return false }
                if code == 53 {
                    self.closePopover()
                    return true
                }
                return self.panel.handleKey(code: code, flags: flags, chars: chars)
            }
            return handled ? nil : event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Settings.clearOnQuit { store.clearUnpinned() }
    }

    private func closePopover() {
        panel.didClose()
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}
