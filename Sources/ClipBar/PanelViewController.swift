import AppKit

/// The popover: search field, history list, footer. Hovering a row opens the side preview.
@MainActor
final class PanelViewController: NSViewController {
    var onClose: (@MainActor () -> Void)?
    var onQuit: (@MainActor () -> Void)?
    var onModalBusy: (@MainActor (Bool) -> Void)?  // true while an alert is up

    private let store: ClipStore
    private let preview = PreviewController()

    // State (only alive while the popover is open)
    private var clips: [Clip] = []
    private var rows: [ClipRow] = []
    private var selected = -1
    private var isOpen = false
    private var suppressHoverUntil = Date.distantPast
    private var mouseOnPreview = false
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    // Views
    private let search = NSSearchField()
    private let list = FlippedStackView()
    private var scroll: NSScrollView!
    private var scrollHeight: NSLayoutConstraint!
    private var stack: NSStackView!
    private let countLabel = UI.label("", size: 11, color: .tertiaryLabelColor)

    init(store: ClipStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)

        preview.onPin = { [weak self] in self?.togglePinSelected() }
        preview.onDelete = { [weak self] in self?.deleteSelected() }
        preview.onMouseInside = { [weak self] inside in
            guard let self else { return }
            self.mouseOnPreview = inside
            if inside { self.hideTask?.cancel() } else { self.scheduleHide() }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: View construction

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: UI.width, height: 300))
        view = root

        search.placeholderString = "Type to search…"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        UI.fixedWidth(search)

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

        let clearBtn = UI.footerButton(
            "Clear", symbol: "trash", target: self, action: #selector(clearTapped))
        let folderBtn = UI.footerButton(
            "Data folder", symbol: "folder", target: self, action: #selector(openFolderTapped))
        let quitBtn = UI.footerButton(
            "Quit", symbol: "power", target: self, action: #selector(quitTapped))
        countLabel.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)
        let footer = UI.row([clearBtn, folderBtn, UI.spacer(), countLabel, quitBtn], spacing: 10)

        stack = NSStackView(views: [search, scroll, UI.separator(), footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: UI.width).isActive = true
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
    }

    // MARK: Called by the app

    /// Before the popover is shown: fill the list so it opens at the right height.
    func prepareForOpen() {
        isOpen = true
        suppressHoverUntil = Date().addingTimeInterval(0.4)  // a resting mouse must not steal the selection
        search.stringValue = ""
        reload(reset: true)
    }

    func focusSearch() { view.window?.makeFirstResponder(search) }

    /// Popover closed: drop every row and image so nothing stays in memory.
    func didClose() {
        isOpen = false
        showTask?.cancel()
        hideTask?.cancel()
        mouseOnPreview = false
        preview.hide()
        for v in list.arrangedSubviews {
            list.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        rows = []
        clips = []
        selected = -1
        search.stringValue = ""
    }

    func storeChanged() { reload(reset: false) }

    /// Keyboard shortcuts while the popover is open. Returns true if the key was used.
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

        applySelection(scroll: false)
        countLabel.stringValue = "\(store.totalCount()) items"
        updateSize()

        if preview.isVisible {
            if selected >= 0 { showPreview() } else { hidePreview() }
        }
    }

    private func rebuildRows() {
        for v in list.arrangedSubviews {
            list.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        rows = []

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
            row.onExit = { [weak self] in self?.scheduleHide() }
            row.onClick = { [weak self] in self?.choose(i) }
            list.addArrangedSubview(row)
            rows.append(row)
        }
    }

    private func applySelection(scroll shouldScroll: Bool) {
        for (i, row) in rows.enumerated() { row.setSelected(i == selected) }
        if shouldScroll, selected >= 0, selected < rows.count {
            rows[selected].scrollToVisible(rows[selected].bounds)
        }
    }

    private func updateSize() {
        let height: CGFloat
        if rows.isEmpty {
            height = 40
        } else {
            height = rows.reduce(0) { $0 + $1.rowHeight } + list.spacing * CGFloat(rows.count - 1)
        }
        scrollHeight.constant = min(max(height, 40), 360)
        stack.layoutSubtreeIfNeeded()
        let total = stack.fittingSize.height
        if abs(preferredContentSize.height - total) > 0.5 || preferredContentSize.width != UI.width
        {
            preferredContentSize = NSSize(width: UI.width, height: total)
        }
    }

    // MARK: Selection

    private func hovered(_ index: Int) {
        guard Date() >= suppressHoverUntil, index != selected || !preview.isVisible else { return }
        selected = index
        applySelection(scroll: false)
        schedulePreview()
    }

    private func move(_ delta: Int) {
        guard !clips.isEmpty else { return }
        selected = min(max(selected + delta, 0), clips.count - 1)
        suppressHoverUntil = Date().addingTimeInterval(0.3)  // rows scroll under a resting mouse
        applySelection(scroll: true)
        schedulePreview()
    }

    /// Copies the item back to the clipboard (it jumps to the top) and closes the popover.
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
        let id = clips[selected].id
        hidePreview()
        store.delete(id)
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
        guard selected >= 0, selected < clips.count, let window = view.window else { return }
        let clip = clips[selected]
        let text: String? = clip.kind == .image ? nil : store.fullText(clip.id)
        let image: NSImage? =
            clip.kind == .image
            ? ImageTools.loadImage(at: store.imageURL(clip), maxPixel: Config.previewPixels) : nil
        preview.show(clip: clip, text: text, image: image, beside: window.frame)
    }

    /// Short grace period so the mouse can travel from the row onto the preview (to reach pin/delete).
    private func scheduleHide() {
        showTask?.cancel()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self, !self.mouseOnPreview else { return }
            self.preview.hide()
        }
    }

    private func hidePreview() {
        showTask?.cancel()
        hideTask?.cancel()
        mouseOnPreview = false
        preview.hide()
    }

    // MARK: Actions

    @objc private func searchChanged() {
        hidePreview()
        reload(reset: true)
    }

    @objc private func clearTapped() {
        let n = store.unpinnedCount()
        guard n > 0 else { return }
        hidePreview()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText =
            "This removes \(n) item\(n == 1 ? "" : "s") and their image files. Pinned items are kept."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        onModalBusy?(true)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        onModalBusy?(false)
        if response == .alertFirstButtonReturn { store.clearUnpinned() }
    }

    @objc private func openFolderTapped() {
        NSWorkspace.shared.open(Config.dataDirectory)
        onClose?()
    }

    @objc private func quitTapped() { onQuit?() }
}
