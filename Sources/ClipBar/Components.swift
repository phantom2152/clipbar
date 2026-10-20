import AppKit

// MARK: - SF Symbols

enum Symbols {
    static func image(_ name: String, size: CGFloat = 14, weight: NSFont.Weight = .medium) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }
}

// MARK: - Formats

@MainActor
enum Formats {
    static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}

// MARK: - Layout helpers

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }     // so scroll content starts at the top
}

@MainActor
enum UI {
    static let width: CGFloat = 340           // popover width
    static let inner: CGFloat = 324           // width minus 8pt insets

    @discardableResult
    static func fixedWidth<V: NSView>(_ v: V, _ width: CGFloat = UI.inner) -> V {
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
        return v
    }

    static func spacer() -> NSView {
        let s = NSView()
        s.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return s
    }

    static func row(_ views: [NSView], spacing: CGFloat = 8, width: CGFloat = UI.inner) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.distribution = .fill
        r.alignment = .centerY
        r.spacing = spacing
        return fixedWidth(r, width)
    }

    static func separator(width: CGFloat = UI.inner) -> NSView {
        let b = NSBox()
        b.boxType = .separator
        return fixedWidth(b, width)
    }

    static func label(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = .systemFont(ofSize: size, weight: weight)
        t.textColor = color
        t.lineBreakMode = .byTruncatingTail
        return t
    }

    static func paragraph(_ s: String, size: CGFloat = 13, color: NSColor = .secondaryLabelColor,
                          width: CGFloat = UI.inner) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: size)
        t.textColor = color
        t.preferredMaxLayoutWidth = width
        return fixedWidth(t, width)
    }

    /// Small borderless text button with a leading symbol (footer actions).
    static func footerButton(_ title: String, symbol: String, target: AnyObject?, action: Selector?) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.isBordered = false
        b.font = .systemFont(ofSize: 12)
        b.image = Symbols.image(symbol, size: 11)
        b.imagePosition = .imageLeading
        b.contentTintColor = .secondaryLabelColor
        return b
    }
}

// MARK: - Icon button

/// Borderless symbol button with a hover highlight.
@MainActor
final class IconButton: NSButton {
    private let side: CGFloat
    private let symbolSize: CGFloat
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { refreshBackground() } }

    init(symbol: String, tooltip: String, side: CGFloat = 28, symbolSize: CGFloat = 14,
         target: AnyObject?, action: Selector?) {
        self.side = side
        self.symbolSize = symbolSize
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        self.target = target
        self.action = action
        toolTip = tooltip
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        setButtonType(.momentaryChange)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: side).isActive = true
        heightAnchor.constraint(equalToConstant: side).isActive = true
        contentTintColor = .secondaryLabelColor
        setSymbol(symbol)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setSymbol(_ name: String) { image = Symbols.image(name, size: symbolSize) }

    private func refreshBackground() {
        layer?.cornerRadius = 7
        layer?.backgroundColor = hovering ? NSColor.labelColor.withAlphaComponent(0.10).cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}
