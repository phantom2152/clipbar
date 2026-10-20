import AppKit

/// One line in the history list: text, or an image thumbnail.
@MainActor
final class ClipRow: NSView {
    var onHover: (@MainActor () -> Void)?
    var onExit: (@MainActor () -> Void)?
    var onClick: (@MainActor () -> Void)?

    let rowHeight: CGFloat
    private var primary: [NSTextField] = []
    private var secondary: [NSTextField] = []
    private var pinIcon: NSImageView?
    private var tracking: NSTrackingArea?

    init(clip: Clip, shortcut: Int?, thumbnail: NSImage?) {
        rowHeight = clip.kind == .image ? 44 : 30
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        widthAnchor.constraint(equalToConstant: UI.inner).isActive = true
        heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        let low = NSLayoutConstraint.Priority(1)
        var views: [NSView] = []

        switch clip.kind {
        case .text, .file:
            let t = NSTextField(labelWithString: clip.preview.isEmpty ? " " : clip.preview)
            t.font = .systemFont(ofSize: 13)
            t.lineBreakMode = .byTruncatingTail
            if clip.kind == .file { t.lineBreakMode = .byTruncatingMiddle }  // keep the file name visible
            t.setContentHuggingPriority(low, for: .horizontal)
            t.setContentCompressionResistancePriority(low, for: .horizontal)
            primary.append(t)
            views.append(t)
        case .image:
            let v = NSImageView()
            v.image = thumbnail
            v.imageScaling = .scaleProportionallyDown
            v.imageAlignment = .alignLeft
            v.translatesAutoresizingMaskIntoConstraints = false
            v.heightAnchor.constraint(equalToConstant: 34).isActive = true
            v.setContentHuggingPriority(low, for: .horizontal)
            v.setContentCompressionResistancePriority(low, for: .horizontal)
            views.append(v)
        }

        if clip.pinned {
            let p = NSImageView()
            p.image = Symbols.image("pin.fill", size: 10)
            p.contentTintColor = .secondaryLabelColor
            p.translatesAutoresizingMaskIntoConstraints = false
            p.setContentHuggingPriority(NSLayoutConstraint.Priority(750), for: .horizontal)
            pinIcon = p
            views.append(p)
        }
        if let shortcut {
            let s = NSTextField(labelWithString: "⌘\(shortcut)")
            s.font = .systemFont(ofSize: 12)
            s.textColor = .tertiaryLabelColor
            secondary.append(s)
            views.append(s)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setSelected(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = selected ? NSColor.controlAccentColor.cgColor : nil
        for t in primary { t.textColor = selected ? .white : .labelColor }
        for t in secondary {
            t.textColor = selected ? NSColor.white.withAlphaComponent(0.75) : .tertiaryLabelColor
        }
        pinIcon?.contentTintColor = selected ? .white : .secondaryLabelColor
    }

    // MARK: Mouse

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

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func mouseDown(with event: NSEvent) {}  // swallow; the click fires on mouse up
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
