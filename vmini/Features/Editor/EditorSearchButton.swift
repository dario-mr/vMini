import AppKit

/// A compact search action with a two-tone keyboard hint.
@MainActor
final class EditorSearchButton: NSButton {
    let actionTitle: String
    let shortcut: String
    private var hoverArea: NSTrackingArea?
    let hint = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)

    init(symbol: String, title: String, shortcut: String) {
        actionTitle = title
        self.shortcut = shortcut
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageOnly
        isBordered = false
        setAccessibilityLabel("\(title) (\(shortcut))")
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        hint.isOpaque = false
        hint.backgroundColor = .clear
        hint.hasShadow = true
        hint.ignoresMouseEvents = true
        hint.hidesOnDeactivate = true
        hint.level = .popUpMenu
        hint.animationBehavior = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard let window else { return }
        let title = NSTextField(labelWithString: actionTitle)
        let key = NSTextField(labelWithString: shortcut)
        title.font = .systemFont(ofSize: 11)
        title.textColor = AppColors.primaryText
        key.font = .systemFont(ofSize: 11)
        key.textColor = .secondaryLabelColor
        let row = NSStackView(views: [title, key])
        row.spacing = 12
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        let size = NSSize(width: row.fittingSize.width + 20, height: row.fittingSize.height + 16)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = AppColors.appBackground.cgColor
        content.layer?.cornerRadius = 6
        content.layer?.borderWidth = 0.5
        content.layer?.borderColor = AppColors.inactiveControlTint.cgColor
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
        hint.contentView = content
        hint.setContentSize(size)
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screen.minX), screen.maxX - size.width)
        let below = anchor.minY - size.height - 6
        hint.setFrameOrigin(NSPoint(x: x, y: below >= screen.minY ? below : anchor.maxY + 6))
        window.addChildWindow(hint, ordered: .above)
        hint.orderFront(nil)
    }

    override func mouseExited(with event: NSEvent) { dismissHint() }

    func dismissHint() {
        hint.parent?.removeChildWindow(hint)
        hint.orderOut(nil)
    }

    override func mouseDown(with event: NSEvent) {
        dismissHint()
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dismissHint() }
    }
}
