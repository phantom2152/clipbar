import AppKit

/// Borderless window that can take key focus (so the search field works).
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Window background that reports when the mouse enters or leaves the whole popup,
/// and tells the panel about every size change (including each frame of the open/close animation).
final class PopupRootView: NSVisualEffectView {
    var onMouse: (@MainActor (Bool) -> Void)?
    var onResize: (@MainActor (NSSize) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onMouse?(true) }
    override func mouseExited(with event: NSEvent) { onMouse?(false) }

    /// Replaces autoresizing: the panel places its columns itself on every size change.
    override func resizeSubviews(withOldSize oldSize: NSSize) { onResize?(bounds.size) }
}

/// One translucent window: [ sidebar (preview) | main column ].
/// The sidebar has the same height and top edge as the main column and grows out to the left on hover.
@MainActor
final class PanelViewController: NSViewController {
    var onClose: (@MainActor () -> Void)?
    var onQuit: (@MainActor () -> Void)?
    var onModalBusy: (@MainActor (Bool) -> Void)?  // true while an alert is up
    var onSettings: (@MainActor () -> Void)?

    private let store: ClipStore
    private let preview = PreviewController()
    private let popup: PopupPanel

    // State (only alive while the panel is open)
    private var clips: [Clip] = []
    private var rows: [ClipRow] = []
    private var selected = -1
    private var isOpen = false
    private var suppressHoverUntil = Date.distantPast
    private var mouseOnPreview = false
    private var sidebarOpen = false
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    // Window placement
    private var anchorRight: CGFloat = 0  // right edge of the main column (screen coords)
    private var anchorTop: CGFloat = 0  // top edge of the window (screen coords)
    private var mainHeight: CGFloat = 300
    private let minMainHeight: CGFloat = 250  // keeps enough room for the sidebar's meta block

    // Views
    private let search = NSSearchField()
    private let list = FlippedStackView()
    private let divider = NSBox()
    private let mainBox = NSView(frame: NSRect(x: 0, y: 0, width: UI.width, height: 300))
    private let pinnedStack = NSStackView()
    private lazy var pinDivider: NSView = pinSeparator()
    private var scroll: NSScrollView!
    private var scrollHeight: NSLayoutConstraint!
    private var mainStack: NSStackView!
    private var footerRows: [MenuRow] = []
    private var footerActive = false
    private let separatorHeight: CGFloat = 7

    var isShown: Bool { popup.isVisible }

    init(store: ClipStore) {
        self.store = store
        popup = PopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: UI.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init(nibName: nil, bundle: nil)

        popup.isOpaque = false
        popup.backgroundColor = .clear
        popup.hasShadow = true
        popup.level = .popUpMenu
        popup.hidesOnDeactivate = false
        popup.isReleasedWhenClosed = false
        popup.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        preview.onPin = { [weak self] in self?.togglePinSelected() }
        preview.onDelete = { [weak self] in self?.deleteSelected() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: View construction

    override func loadView() {
        let root = PopupRootView(frame: NSRect(x: 0, y: 0, width: UI.width, height: 300))
        root.material = .hudWindow
        root.state = .active
        root.blendingMode = .behindWindow
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        view = root

        root.onMouse = { [weak self] inside in
            guard let self else { return }
            if inside { self.hideTask?.cancel() } else { self.scheduleHide() }
        }
        root.onResize = { [weak self] size in self?.placeColumns(size) }

        // Header: app name + search field
        search.placeholderString = "Type to search…"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        search.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let title = UI.label("ClipBar", size: 13, weight: .semibold, color: .secondaryLabelColor)
        let header = UI.row([title, search], spacing: 8)
        header.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)

        // History list
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2
        list.translatesAutoresizingMaskIntoConstraints = false

        scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = list
        UI.fixedWidth(scroll)
        scrollHeight = scroll.heightAnchor.constraint(equalToConstant: 200)
        scrollHeight.isActive = true
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: clip.topAnchor),
            list.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
        ])

        // Footer: stacked rows
        footerRows = [
            menuRow("Clear", symbol: "trash") { [weak self] in self?.clearTapped() },
            menuRow("Data folder", symbol: "folder") { [weak self] in self?.openFolderTapped() },
            menuRow("Settings", symbol: "gearshape") { [weak self] in self?.settingsTapped() },
            menuRow("Quit", symbol: "power") { [weak self] in self?.quitTapped() },
        ]
        let footer = NSStackView(views: footerRows)
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 0

        pinnedStack.orientation = .vertical
        pinnedStack.alignment = .leading
        pinnedStack.spacing = 2
        UI.fixedWidth(pinnedStack)
        pinnedStack.isHidden = true
        pinDivider.isHidden = true

        mainStack = NSStackView(views: [
            header, pinnedStack, pinDivider, scroll, UI.separator(), footer,
        ])
        mainStack.setCustomSpacing(2, after: pinnedStack)
        mainStack.setCustomSpacing(2, after: pinDivider)
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 6
        mainStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainBox.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: mainBox.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: mainBox.leadingAnchor),
            mainStack.widthAnchor.constraint(equalToConstant: UI.width),
        ])

        divider.boxType = .separator
        divider.isHidden = true
        mainBox.autoresizingMask = []
        preview.view.autoresizingMask = []

        // Columns are placed by frame in placeColumns(), not by constraints or autoresizing.
        root.addSubview(preview.view)
        root.addSubview(mainBox)
        root.addSubview(divider)
        placeColumns(root.bounds.size)
        popup.contentView = root
    }

    /// One full-width, borderless row for the footer.
    private func menuRow(
        _ title: String, symbol: String,
        action: @escaping @MainActor () -> Void
    ) -> MenuRow {
        let row = MenuRow(title: title, symbol: symbol)
        row.onClick = action
        row.onHover = { [weak self, weak row] in
            guard let self, let row else { return }
            self.footerHovered(row)
        }
        return row
    }

    // MARK: Called by the app

    /// Before the panel is shown: fill the list so it opens at the right height.
    func prepareForOpen() {
        clearFooter()
        isOpen = true
        suppressHoverUntil = Date().addingTimeInterval(0.4)  // a resting mouse must not steal the selection
        search.stringValue = ""
        reload(reset: true)
    }

    /// Places the window under the menu bar icon and shows it.
    func show(below button: NSView) {
        guard let bw = button.window else { return }
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let visible =
            (bw.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let mainX = min(max(b.midX - 170, visible.minX + 6), visible.maxX - UI.width - 6)
        anchorRight = mainX + UI.width
        anchorTop = b.minY - 4
        layoutWindow()
        popup.makeKeyAndOrderFront(nil)
        popup.orderFrontRegardless()
    }

    func focusSearch() { popup.makeFirstResponder(search) }

    /// Panel closed: drop every row and image so nothing stays in memory.
    func didClose() {
        isOpen = false
        popup.orderOut(nil)
        showTask?.cancel()
        hideTask?.cancel()
        mouseOnPreview = false
        sidebarOpen = false
        preview.hide()
        finishClose()
        clearFooter()
        clearRows()
        clips = []
        selected = -1
        search.stringValue = ""
    }

    func storeChanged() { reload(reset: false) }

    /// Keyboard shortcuts while the panel is open. Returns true if the key was used.
    func handleKey(code: UInt16, flags: NSEvent.ModifierFlags, chars: String) -> Bool {
        guard isOpen else { return false }
        let cmd = flags.contains(.command)
        let opt = flags.contains(.option)

        switch code {
        case 126:
            move(-1)
            return true  // up
        case 125:
            move(1)
            return true  // down
        case 36, 76:  // return / enter
            if selected >= 0, selected < clips.count { choose(selected) }
            return true
        case 51, 117:  // delete
            guard cmd else { return false }
            if opt { clearTapped() } else { deleteSelected() }
            return true
        default: break
        }
        if cmd, let c = chars.first {
            if c == "p" {
                togglePinSelected()
                return true
            }
            if let n = Int(String(c)), (1...9).contains(n) {
                if n - 1 < clips.count { choose(n - 1) }
                return true
            }
        }
        return false
    }

    // MARK: Window size

    /// Main column: fixed width, always at the right. Sidebar: the space left of it, with its content
    /// pinned against the main column, so nothing overlaps or squeezes while the window grows or shrinks.
    /// Called on every size change of the window, including each frame of the open/close animation.
    private func placeColumns(_ size: NSSize) {
        let side = max(size.width - UI.width, 0)
        let h = size.height
        mainBox.frame = NSRect(x: side, y: 0, width: UI.width, height: h)
        preview.view.frame = NSRect(
            x: side - PreviewController.width, y: 0, width: PreviewController.width, height: h)
        divider.frame = NSRect(x: max(side - 1, 0), y: 0, width: 1, height: h)
        divider.isHidden = side < 1
    }

    /// Window = main column (+ sidebar on its left while open). Right edge and top edge stay fixed.
    /// Only a width change (sidebar opening or closing) animates; everything else is instant.
    private func layoutWindow(animated: Bool = false) {
        let w = UI.width + (sidebarOpen ? PreviewController.width : 0)
        let h = mainHeight
        let frame = NSRect(x: anchorRight - w, y: anchorTop - h, width: w, height: h)

        if animated, popup.isVisible, abs(popup.frame.width - w) > 0.5 {
            NSAnimationContext.runAnimationGroup(
                { ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    popup.animator().setFrame(frame, display: true)
                },
                completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        self?.finishClose()
                        self?.popup.invalidateShadow()
                    }
                })
        } else {
            popup.setFrame(frame, display: true)
            finishClose()
            popup.invalidateShadow()
        }
    }

    /// After the sidebar has slid shut: free the content (and any decoded image).
    private func finishClose() {
        guard !sidebarOpen else { return }
        preview.finishHide()
    }

    // MARK: List

    private func reload(reset: Bool) {
        guard isViewLoaded, isOpen else { return }
        let oldIndex = selected
        let oldID = (!reset && oldIndex >= 0 && oldIndex < clips.count) ? clips[oldIndex].id : nil

        clips = store.list(search: search.stringValue)
        rebuildRows()

        if clips.isEmpty {
            selected = -1
        } else if let oldID, let i = clips.firstIndex(where: { $0.id == oldID }) {
            selected = i
        } else if reset {
            selected = 0
        } else {
            selected = min(max(oldIndex, 0), clips.count - 1)
        }
        if footerActive { selected = -1 }  // a footer row owns the highlight
        applySelection(scroll: false)
        search.placeholderString = "Search \(store.totalCount()) items…"
        updateSize()

        if preview.isVisible {
            if selected >= 0 { showPreview() } else { hidePreview() }
        }
    }

    private func clearRows() {
        for stack in [pinnedStack, list] as [NSStackView] {
            for v in stack.arrangedSubviews {
                stack.removeArrangedSubview(v)
                v.removeFromSuperview()
            }
        }
        rows = []
    }

    private func rebuildRows() {
        clearRows()
        let hasPinned = clips.contains { $0.pinned }
        let hasUnpinned = clips.contains { !$0.pinned }
        pinnedStack.isHidden = !hasPinned
        pinDivider.isHidden = !(hasPinned && hasUnpinned)

        if clips.isEmpty {
            let msg =
                search.stringValue.isEmpty
                ? "Nothing copied yet. Copy some text or an image." : "No matches."
            list.addArrangedSubview(UI.paragraph(msg, size: 12, color: .tertiaryLabelColor))
            return
        }
        for (i, clip) in clips.enumerated() {
            let thumb: NSImage? =
                clip.kind == .image ? NSImage(contentsOf: store.thumbURL(clip)) : nil
            let row = ClipRow(clip: clip, shortcut: i < 9 ? i + 1 : nil, thumbnail: thumb)
            row.onHover = { [weak self] in self?.hovered(i) }
            row.onClick = { [weak self] in self?.choose(i) }
            (clip.pinned ? pinnedStack : list).addArrangedSubview(row)
            rows.append(row)
        }
    }

    private func pinSeparator() -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(line)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: UI.inner),
            box.heightAnchor.constraint(equalToConstant: separatorHeight),
            line.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            line.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            line.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    private func applySelection(scroll shouldScroll: Bool) {
        for (i, row) in rows.enumerated() { row.setSelected(i == selected) }
        if shouldScroll, selected >= 0, selected < rows.count {
            rows[selected].scrollToVisible(rows[selected].bounds)
        }
    }

    private func updateSize() {
        var pinnedH: CGFloat = 0
        var unpinnedH: CGFloat = 0
        var pinnedN = 0
        var unpinnedN = 0
        for (i, row) in rows.enumerated() {
            if clips[i].pinned {
                pinnedH += row.rowHeight
                pinnedN += 1
            } else {
                unpinnedH += row.rowHeight
                unpinnedN += 1
            }
        }
        pinnedH += list.spacing * CGFloat(max(pinnedN - 1, 0))
        unpinnedH += list.spacing * CGFloat(max(unpinnedN - 1, 0))

        // Only the unpinned part scrolls; the pinned block eats into the 360pt cap.
        let fixedH = pinnedN > 0 ? pinnedH + (unpinnedN > 0 ? separatorHeight + 4 : 0) : 0
        let cap = max(360 - fixedH, 120)
        let wanted: CGFloat = rows.isEmpty ? 40 : (unpinnedN > 0 ? max(unpinnedH, 40) : 0)
        scrollHeight.constant = min(wanted, cap)
        mainStack.layoutSubtreeIfNeeded()

        var total = mainStack.fittingSize.height
        if total < minMainHeight {  // few items: pad so the sidebar's meta block fits
            scrollHeight.constant += minMainHeight - total
            mainStack.layoutSubtreeIfNeeded()
            total = minMainHeight
        }
        mainHeight = total
        if popup.isVisible { layoutWindow() }
    }

    // MARK: Selection

    private func hovered(_ index: Int) {
        guard Date() >= suppressHoverUntil else { return }
        clearFooter()
        hideTask?.cancel()
        guard index != selected || !preview.isVisible else { return }
        selected = index
        applySelection(scroll: false)
        schedulePreview()
    }

    private func move(_ delta: Int) {
        guard !clips.isEmpty else { return }
        clearFooter()
        selected = min(max(selected + delta, 0), clips.count - 1)
        suppressHoverUntil = Date().addingTimeInterval(0.3)  // rows scroll under a resting mouse
        applySelection(scroll: true)
        schedulePreview()
    }

    /// Copies the item back to the clipboard (it jumps to the top) and closes the panel.
    private func choose(_ index: Int) {
        guard index >= 0, index < clips.count else { return }
        store.copyToPasteboard(clips[index])
        onClose?()
    }

    private func togglePinSelected() {
        guard selected >= 0, selected < clips.count else { return }
        store.togglePin(clips[selected].id)  // storeChanged() refreshes list + preview
    }

    private func deleteSelected() {
        guard selected >= 0, selected < clips.count else { return }
        store.delete(clips[selected].id)  // storeChanged() reselects the neighbour and refreshes the sidebar
    }

    /// Mouse entered a footer row: it takes the highlight, the list gives up its selection.
    private func footerHovered(_ row: MenuRow) {
        guard isOpen, Date() >= suppressHoverUntil else { return }
        showTask?.cancel()
        hideTask?.cancel()
        footerActive = true
        selected = -1
        applySelection(scroll: false)
        hidePreview()
        for r in footerRows { r.setHighlighted(r === row) }
    }

    private func clearFooter() {
        footerActive = false
        for r in footerRows { r.setHighlighted(false) }
    }

    // MARK: Preview

    private func schedulePreview() {
        showTask?.cancel()
        hideTask?.cancel()
        guard selected >= 0, selected < clips.count else {
            hidePreview()
            return
        }
        let id = clips[selected].id
        let delay: UInt64 = preview.isVisible ? 120_000_000 : 350_000_000
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.isOpen,
                self.selected >= 0, self.selected < self.clips.count,
                self.clips[self.selected].id == id
            else { return }
            self.showPreview()
        }
    }

    private func showPreview() {
        guard selected >= 0, selected < clips.count else { return }
        let clip = clips[selected]
        let text: String? = clip.kind == .image ? nil : store.fullText(clip.id)
        let image: NSImage? =
            clip.kind == .image
            ? ImageTools.loadImage(at: store.imageURL(clip), maxPixel: Config.previewPixels) : nil
        sidebarOpen = true
        preview.show(clip: clip, text: text, image: image)
        layoutWindow(animated: true)
    }

    /// Short grace period before the sidebar closes when the mouse leaves the whole window.
    private func scheduleHide() {
        showTask?.cancel()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self, !self.mouseOnPreview else { return }
            self.dismissPreview()
        }
    }

    private func hidePreview() {
        showTask?.cancel()
        hideTask?.cancel()
        mouseOnPreview = false
        dismissPreview()
    }

    private func dismissPreview() {
        sidebarOpen = false
        preview.hide()
        if popup.isVisible { layoutWindow(animated: true) } else { finishClose() }
    }

    // MARK: Actions

    @objc private func searchChanged() {
        clearFooter()
        hidePreview()
        reload(reset: true)
    }

    @objc private func clearTapped() {
        let n = store.unpinnedCount()
        guard n > 0 else { return }
        hidePreview()
        guard Settings.confirmClear else {
            store.clearUnpinned()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText =
            "This removes \(n) item\(n == 1 ? "" : "s") and their image files. Pinned items are kept."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true  // red text, system styling does the rest
        for b in alert.buttons { b.keyEquivalent = "" }  // neither is default: the user must click
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        onModalBusy?(true)
        suppressHoverUntil = .distantFuture  // rows behind the sheet must not open the sidebar
        alert.beginSheetModal(for: popup) { [weak self] response in
            guard let self else { return }
            self.onModalBusy?(false)
            self.suppressHoverUntil = Date().addingTimeInterval(0.3)
            if alert.suppressionButton?.state == .on { Settings.confirmClear = false }
            if response == .alertFirstButtonReturn { self.store.clearUnpinned() }
        }
    }

    @objc private func openFolderTapped() {
        NSWorkspace.shared.open(Config.dataDirectory)
        onClose?()
    }

    @objc private func settingsTapped() { onSettings?() }

    @objc private func quitTapped() { onQuit?() }
}
