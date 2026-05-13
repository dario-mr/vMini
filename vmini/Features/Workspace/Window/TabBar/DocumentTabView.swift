import AppKit

final class DocumentTabView: NSView {
    private enum Layout {
        static let titleLeadingInset: CGFloat = 12
        static let titleToCloseButtonSpacing: CGFloat = 12
        static let closeButtonTrailingInset: CGFloat = 10
        static let closeButtonSize: CGFloat = 12
    }

    private enum Typography {
        static let fontSize: CGFloat = 12
        static let activeWeight: NSFont.Weight = .regular
        static let inactiveWeight: NSFont.Weight = .regular
    }

    weak var document: Document?

    var onSelect: ((Document) -> Void)?
    var onClose: ((Document) -> Void)?
    var onCloseOthers: ((Document) -> Void)?
    var onCloseAll: (() -> Void)?
    var onDragStarted: ((DocumentTabView, NSPoint) -> Void)?
    var onDragMoved: ((DocumentTabView, NSPoint) -> Void)?
    var onDragEnded: ((DocumentTabView) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isActive = false
    private var dragStartLocationInWindow: NSPoint?
    private var isDraggingTab = false
    private let hoverFadeDuration: CFTimeInterval = 0.16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        closeButton.target = self
        closeButton.action = #selector(handleCloseButton)
        closeButton.contentTintColor = AppColors.defaultControlTint
        closeButton.setButtonType(.momentaryChange)

        addSubview(titleLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: EditorTabBarLayout.tabHeight),
            widthAnchor.constraint(greaterThanOrEqualToConstant: EditorTabBarLayout.minimumTabWidth),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.titleLeadingInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -Layout.titleToCloseButtonSpacing),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.closeButtonTrailingInset),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Layout.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Layout.closeButtonSize),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseDown(with event: NSEvent) {
        guard let document else { return }
        dragStartLocationInWindow = event.locationInWindow
        isDraggingTab = false
        onSelect?(document)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartLocationInWindow else { return }

        let deltaX = event.locationInWindow.x - dragStartLocationInWindow.x
        let deltaY = event.locationInWindow.y - dragStartLocationInWindow.y
        if !isDraggingTab, hypot(deltaX, deltaY) >= 4 {
            isDraggingTab = true
            onDragStarted?(self, event.locationInWindow)
        }

        guard isDraggingTab else { return }
        onDragMoved?(self, event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartLocationInWindow = nil
            isDraggingTab = false
        }

        guard isDraggingTab else { return }
        onDragEnded?(self)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let document else {
            super.otherMouseUp(with: event)
            return
        }

        onClose?(document)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard document != nil else {
            super.rightMouseDown(with: event)
            return
        }

        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearance()
    }

    func refreshAppearance() {
        applyAppearance()
    }

    func configure(document: Document, isActive: Bool) {
        self.document = document
        self.isActive = isActive
        titleLabel.stringValue = document.shortDisplayTitle
        applyAppearance()
    }

    func preferredWidth() -> CGFloat {
        let titleWidth = ceil(titleLabel.intrinsicContentSize.width)
        let contentWidth = Layout.titleLeadingInset
            + titleWidth
            + Layout.titleToCloseButtonSpacing
            + Layout.closeButtonSize
            + Layout.closeButtonTrailingInset
        return min(max(contentWidth, EditorTabBarLayout.minimumTabWidth), EditorTabBarLayout.maximumTabWidth)
    }

    private func applyAppearance() {
        guard let layer else { return }

        layer.masksToBounds = true
        layer.cornerRadius = 0
        layer.mask = makeTopRoundedMaskLayer()

        if isActive {
            setBackgroundColor(AppColors.editorBackground.cgColor, animated: false)
            titleLabel.textColor = AppColors.primaryText
            titleLabel.font = NSFont.systemFont(ofSize: Typography.fontSize, weight: Typography.activeWeight)
            closeButton.contentTintColor = AppColors.activeControlTint
        } else {
            let backgroundColor = (isHovered
                ? AppColors.hoveredTabBackground
                : AppColors.tabBarBackground).cgColor
            setBackgroundColor(backgroundColor, animated: true)
            titleLabel.textColor = isHovered ? AppColors.sidebarText : AppColors.inactiveTabText
            titleLabel.font = NSFont.systemFont(ofSize: Typography.fontSize, weight: Typography.inactiveWeight)
            closeButton.contentTintColor = isHovered ? AppColors.hoveredControlTint : AppColors.inactiveControlTint
        }
    }

    private func setBackgroundColor(_ color: CGColor, animated: Bool) {
        guard let layer else { return }
        let previousColor = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        layer.backgroundColor = color

        guard
            animated,
            let previousColor,
            previousColor != color
        else {
            return
        }

        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = previousColor
        animation.toValue = color
        animation.duration = hoverFadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "backgroundColorFade")
    }

    override func layout() {
        super.layout()
        layer?.mask = makeTopRoundedMaskLayer()
    }

    private func makeTopRoundedMaskLayer() -> CAShapeLayer {
        let radius: CGFloat = 6
        let rect = bounds
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()

        let maskLayer = CAShapeLayer()
        maskLayer.frame = rect
        maskLayer.path = path
        return maskLayer
    }

    @objc
    private func handleCloseButton() {
        guard let document else { return }
        onClose?(document)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Close", action: #selector(closeFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close Others", action: #selector(closeOthersFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close All", action: #selector(closeAllFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy Path", action: #selector(copyPathFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show in Finder", action: #selector(showInFinderFromMenu), keyEquivalent: ""))

        for item in menu.items {
            item.target = self
        }

        return menu
    }

    @objc
    private func closeFromMenu() {
        guard let document else { return }
        onClose?(document)
    }

    @objc
    private func closeOthersFromMenu() {
        guard let document else { return }
        onCloseOthers?(document)
    }

    @objc
    private func closeAllFromMenu() {
        onCloseAll?()
    }

    @objc
    private func copyPathFromMenu() {
        guard let path = document?.fileURL?.path else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    @objc
    private func showInFinderFromMenu() {
        guard let fileURL = document?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}

extension DocumentTabView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copyPathFromMenu)
            || menuItem.action == #selector(showInFinderFromMenu) {
            return document?.fileURL != nil
        }

        return true
    }
}
