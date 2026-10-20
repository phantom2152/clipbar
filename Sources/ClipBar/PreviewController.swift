import AppKit

/// Plain view that reports when the mouse is over it.
final class HoverView: NSView {
    var onMouse: (@MainActor (Bool) -> Void)?
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
}

/// The sidebar: [pin/delete header] [scrollable content] [fixed meta block].
/// It is a plain view; PanelViewController sets its frame (same height as the main column).
@MainActor
final class PreviewController: NSObject {
    static let width: CGFloat = 300

    var onPin: (@MainActor () -> Void)?
    var onDelete: (@MainActor () -> Void)?
    var onMouseInside: (@MainActor (Bool) -> Void)?

    let view = HoverView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    private(set) var isVisible = false

    private let contentWidth: CGFloat = 276  // sidebar width minus 12pt insets
    private let textWidth: CGFloat = 268  // a little narrower, leaves room for the scroller

    private var pin: IconButton!
    private var trash: IconButton!
    private let scroll = NSScrollView()
    private let content = FlippedStackView()  // scrolling body
    private let meta = NSStackView()  // fixed details at the bottom

    override init() {
        super.init()
        view.isHidden = true
        view.onMouse = { [weak self] inside in self?.onMouseInside?(inside) }

        pin = IconButton(
            symbol: "pin", tooltip: "Pin", side: 26, symbolSize: 13,
            target: self, action: #selector(pinTapped))
        trash = IconButton(
            symbol: "trash", tooltip: "Delete", side: 26, symbolSize: 13,
            target: self, action: #selector(deleteTapped))
        let header = UI.row([UI.spacer(), pin, trash], spacing: 2, width: contentWidth)

        // Scrollable body
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        // The scroll area takes all the space the header and meta block don't need.
        scroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        scroll.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .vertical)
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: clip.topAnchor),
            content.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
        ])

        // Fixed meta block
        meta.orientation = .vertical
        meta.alignment = .leading
        meta.spacing = 4
        UI.fixedWidth(meta, contentWidth)

        let column = NSStackView(views: [header, scroll, UI.separator(width: contentWidth), meta])
        column.orientation = .vertical
        column.alignment = .leading
        column.distribution = .fill
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)

        let bottom = column.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        bottom.priority = NSLayoutConstraint.Priority(750)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.topAnchor),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.widthAnchor.constraint(equalToConstant: Self.width),
            bottom,
        ])
    }

    /// Marks the sidebar as closed. The content stays until finishHide() so it can slide out.
    func hide() { isVisible = false }

    /// Drops the content (and any decoded image) so nothing stays in memory.
    func finishHide() {
        guard !isVisible else { return }
        view.isHidden = true
        clear(content)
        clear(meta)
    }
    func show(clip: Clip, text: String?, image: NSImage?) {
        pin.setSymbol(clip.pinned ? "pin.slash" : "pin")
        pin.toolTip = clip.pinned ? "Unpin" : "Pin"

        // Scrollable body
        clear(content)
        switch clip.kind {
        case .text:
            let shown = String((text ?? clip.preview).prefix(5000))
            content.addArrangedSubview(bodyText(shown, truncate: .byTruncatingTail))
        case .file:
            let paths = (text ?? "").split(separator: "\n").compactMap {
                URL(string: String($0))?.path
            }
            content.addArrangedSubview(
                bodyText(paths.prefix(50).joined(separator: "\n"), truncate: .byTruncatingMiddle))
        case .image:
            if let image {
                let px = image.size
                let scale = min(textWidth / max(px.width, 1), 1)
                let v = NSImageView()
                v.image = image
                v.imageScaling = .scaleProportionallyUpOrDown
                v.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    v.widthAnchor.constraint(equalToConstant: max(1, px.width * scale)),
                    v.heightAnchor.constraint(equalToConstant: max(1, px.height * scale)),
                ])
                content.addArrangedSubview(v)
            } else {
                content.addArrangedSubview(
                    UI.paragraph("Image file not found.", size: 12, width: textWidth))
            }
        }

        // Fixed meta block
        clear(meta)
        if !clip.source.isEmpty { meta.addArrangedSubview(appRow(clip)) }
        if clip.kind == .image {
            meta.addArrangedSubview(info("Dimensions", "\(clip.width)×\(clip.height)"))
        }
        meta.addArrangedSubview(info("Size", Formats.bytes(clip.bytes)))
        meta.addArrangedSubview(info("First copy time", Formats.full.string(from: clip.firstAt)))
        meta.addArrangedSubview(info("Last copy time", Formats.full.string(from: clip.lastAt)))
        meta.addArrangedSubview(info("Number of copies", "\(clip.copies)"))

        isVisible = true
        view.isHidden = false

        content.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: .zero)  // always start at the top
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: Internals

    private func clear(_ stack: NSStackView) {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
    }

    private func bodyText(_ s: String, truncate: NSLineBreakMode) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: 12)
        t.lineBreakMode = .byWordWrapping
        t.preferredMaxLayoutWidth = textWidth
        return UI.fixedWidth(t, textWidth)
    }

    private func info(_ key: String, _ value: String) -> NSTextField {
        let s = NSMutableAttributedString(
            string: key + ": ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        s.append(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.labelColor,
                ]))
        let t = NSTextField(wrappingLabelWithString: "")
        t.attributedStringValue = s
        t.preferredMaxLayoutWidth = contentWidth
        return UI.fixedWidth(t, contentWidth)
    }

    /// "Application: [icon] Name"
    private func appRow(_ clip: Clip) -> NSView {
        let key = NSTextField(labelWithString: "Application:")
        key.font = .systemFont(ofSize: 11)
        key.textColor = .secondaryLabelColor

        let name = NSTextField(labelWithString: clip.source)
        name.font = .systemFont(ofSize: 11)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        name.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)

        var views: [NSView] = [key]
        if let icon = Self.appIcon(for: clip) {
            let v = NSImageView()
            v.image = icon
            v.imageScaling = .scaleProportionallyUpOrDown
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 15).isActive = true
            v.heightAnchor.constraint(equalToConstant: 15).isActive = true
            views.append(v)
        }
        views.append(name)
        return UI.row(views, spacing: 4, width: contentWidth)
    }

    /// Looked up on demand and never stored. Older entries (no bundle id saved) fall back to a running app with that name.
    private static func appIcon(for clip: Clip) -> NSImage? {
        var url: URL?
        if !clip.sourceBundleID.isEmpty {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clip.sourceBundleID)
        } else {
            url =
                NSWorkspace.shared.runningApplications.first { $0.localizedName == clip.source }?
                .bundleURL
        }
        guard let url else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    @objc private func pinTapped() { onPin?() }
    @objc private func deleteTapped() { onDelete?() }
}
