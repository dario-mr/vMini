import AppKit

/// A compact search action with a two-tone keyboard hint.
@MainActor
final class EditorSearchButton: NSButton {
    @MainActor
    private enum Constants {
        static let fontSize: CGFloat = 12
        static let rowSpacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 6
        static let borderWidth: CGFloat = 0.5
        static let buttonGap: CGFloat = 6
        static var titleColor: NSColor { AppColors.primaryText }
        static var shortcutColor: NSColor { .secondaryLabelColor }
        static var backgroundColor: NSColor { AppColors.appBackground }
        static var borderColor: NSColor { AppColors.inactiveControlTint }
    }

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
        title.font = .systemFont(ofSize: Constants.fontSize)
        title.textColor = Constants.titleColor
        key.font = .systemFont(ofSize: Constants.fontSize)
        key.textColor = Constants.shortcutColor
        let row = NSStackView(views: [title, key])
        row.spacing = Constants.rowSpacing
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        let size = NSSize(
            width: row.fittingSize.width + 2 * Constants.horizontalPadding,
            height: row.fittingSize.height + 2 * Constants.verticalPadding
        )
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = Constants.backgroundColor.cgColor
        content.layer?.cornerRadius = Constants.cornerRadius
        content.layer?.borderWidth = Constants.borderWidth
        content.layer?.borderColor = Constants.borderColor.cgColor
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Constants.horizontalPadding),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Constants.horizontalPadding),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: Constants.verticalPadding),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Constants.verticalPadding),
        ])
        hint.contentView = content
        hint.setContentSize(size)
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screen.minX), screen.maxX - size.width)
        let below = anchor.minY - size.height - Constants.buttonGap
        hint.setFrameOrigin(NSPoint(x: x, y: below >= screen.minY ? below : anchor.maxY + Constants.buttonGap))
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
