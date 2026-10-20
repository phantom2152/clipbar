import AppKit

/// Panel that never takes focus, so typing in the search field keeps working.
final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Blurred background that reports when the mouse is over it.
final class HoverEffectView: NSVisualEffectView {
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

/// The side panel shown next to the popover: full preview, details, pin and delete.
@MainActor
final class PreviewController: NSObject {
    var onPin: (@MainActor () -> Void)?
    var onDelete: (@MainActor () -> Void)?
    var onMouseInside: (@MainActor (Bool) -> Void)?

    private let panel: NonKeyPanel
    private let box = HoverEffectView()
    private let stack = NSStackView()
    private let panelWidth: CGFloat = 300
    private let contentWidth: CGFloat = 276

    var isVisible: Bool { panel.isVisible }

    override init() {
        panel = NonKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        box.material = .popover
        box.state = .active
        box.blendingMode = .behindWindow
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.masksToBounds = true
        box.onMouse = { [weak self] inside in self?.onMouseInside?(inside) }
        panel.contentView = box

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: panelWidth),
        ])
    }

    func hide() { panel.orderOut(nil) }

    /// `anchor` is the popover window's frame; the panel opens beside it.
    func show(clip: Clip, text: String?, image: NSImage?, beside anchor: NSRect) {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        // Header: pin + delete, right aligned
        let pin = IconButton(
            symbol: clip.pinned ? "pin.slash" : "pin",
            tooltip: clip.pinned ? "Unpin" : "Pin",
            side: 26, symbolSize: 13, target: self, action: #selector(pinTapped))
        let trash = IconButton(
            symbol: "trash", tooltip: "Delete",
            side: 26, symbolSize: 13, target: self, action: #selector(deleteTapped))
        stack.addArrangedSubview(
            UI.row([UI.spacer(), pin, trash], spacing: 2, width: contentWidth))

        // Body: whole text (first part) or the image
        switch clip.kind {
        case .text:
            let shown = String((text ?? clip.preview).prefix(3000))
            let t = NSTextField(wrappingLabelWithString: shown)
            t.font = .systemFont(ofSize: 12)
            t.maximumNumberOfLines = 16
            t.lineBreakMode = .byTruncatingTail
            t.cell?.truncatesLastVisibleLine = true
            t.preferredMaxLayoutWidth = contentWidth
            UI.fixedWidth(t, contentWidth)
            stack.addArrangedSubview(t)
        case .image:
            if let image {
                let px = image.size
                let scale = min(contentWidth / max(px.width, 1), 240 / max(px.height, 1), 1)
                let v = NSImageView()
                v.image = image
                v.imageScaling = .scaleProportionallyUpOrDown
                v.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    v.widthAnchor.constraint(equalToConstant: max(1, px.width * scale)),
                    v.heightAnchor.constraint(equalToConstant: max(1, px.height * scale)),
                ])
                stack.addArrangedSubview(v)
            } else {
                stack.addArrangedSubview(
                    UI.paragraph("Image file not found.", size: 12, width: contentWidth))
            }
        case .file:
            let paths = (text ?? "").split(separator: "\n").compactMap {
                URL(string: String($0))?.path
            }
            let t = NSTextField(wrappingLabelWithString: paths.prefix(20).joined(separator: "\n"))
            t.font = .systemFont(ofSize: 12)
            t.maximumNumberOfLines = 16
            t.lineBreakMode = .byTruncatingMiddle
            t.preferredMaxLayoutWidth = contentWidth
            UI.fixedWidth(t, contentWidth)
            stack.addArrangedSubview(t)
        }

        stack.addArrangedSubview(UI.separator(width: contentWidth))

        // Details
        if !clip.source.isEmpty { stack.addArrangedSubview(info("Application", clip.source)) }
        if clip.kind == .image {
            stack.addArrangedSubview(info("Dimensions", "\(clip.width)×\(clip.height)"))
        }
        stack.addArrangedSubview(info("Size", Formats.bytes(clip.bytes)))
        stack.addArrangedSubview(info("First copy time", Formats.full.string(from: clip.firstAt)))
        stack.addArrangedSubview(info("Last copy time", Formats.full.string(from: clip.lastAt)))
        stack.addArrangedSubview(info("Number of copies", "\(clip.copies)"))

        stack.layoutSubtreeIfNeeded()
        let size = NSSize(width: panelWidth, height: stack.fittingSize.height)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size, beside: anchor))
        panel.orderFrontRegardless()
    }

    // MARK: Internals

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

    /// Left of the popover, top aligned; flips to the right side if there is no room.
    private func origin(for size: NSSize, beside anchor: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.minX - size.width - 4
        if x < visible.minX + 4 { x = anchor.maxX + 4 }
        let top = anchor.maxY - 14
        let y = max(top - size.height, visible.minY + 4)
        return NSPoint(x: x, y: y)
    }

    @objc private func pinTapped() { onPin?() }
    @objc private func deleteTapped() { onDelete?() }
}
