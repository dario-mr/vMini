import AppKit

@MainActor
final class AppButton: NSButton {
    enum Style {
        case primary
        case secondary
    }

    enum Layout {
        static let minimumWidth: CGFloat = 68
        static let height: CGFloat = 28
        static let cornerRadius: CGFloat = 8
        static let secondaryBorderWidth: CGFloat = 0.8
        static let hoverOverlayOpacity: Float = 0.2
        static let hoverAnimationDuration: CFTimeInterval = 0.17
    }

    var style: Style {
        didSet {
            applyTheme()
        }
    }

    private let hoverOverlayLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var themeObservation: ObservationToken?

    init(title: String, style: Style) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        wantsLayer = true
        font = NSFont.systemFont(ofSize: 12, weight: .medium)
        contentTintColor = nil
        imagePosition = .noImage
        setContentHuggingPriority(.required, for: .horizontal)

        hoverOverlayLayer.backgroundColor = NSColor.black.cgColor
        hoverOverlayLayer.opacity = 0
        hoverOverlayLayer.cornerRadius = Layout.cornerRadius

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumWidth),
            heightAnchor.constraint(equalToConstant: Layout.height),
        ])

        applyTheme()

        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.applyTheme()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var title: String {
        didSet {
            applyTheme()
        }
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

    override func layout() {
        super.layout()
        hoverOverlayLayer.frame = bounds
        hoverOverlayLayer.cornerRadius = Layout.cornerRadius
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        applyHoverState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        applyHoverState(animated: true)
    }

    private func applyTheme() {
        if hoverOverlayLayer.superlayer == nil {
            layer?.addSublayer(hoverOverlayLayer)
        }
        layer?.cornerRadius = Layout.cornerRadius

        switch style {
        case .primary:
            layer?.borderWidth = 0
            layer?.borderColor = nil
            layer?.backgroundColor = AppColors.primaryActionBackground.cgColor
            applyTitleColor(AppColors.primaryActionText)
        case .secondary:
            layer?.borderWidth = Layout.secondaryBorderWidth
            layer?.borderColor = AppColors.inactiveControlTint.cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
            applyTitleColor(AppColors.primaryText)
        }

        applyHoverState(animated: false)
    }

    private func applyTitleColor(_ color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
        ]
        attributedTitle = NSAttributedString(string: title, attributes: attributes)
        attributedAlternateTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func applyHoverState(animated: Bool) {
        let targetOpacity: Float = isHovered ? Layout.hoverOverlayOpacity : 0

        guard animated else {
            hoverOverlayLayer.removeAnimation(forKey: "hoverOpacity")
            hoverOverlayLayer.opacity = targetOpacity
            return
        }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = hoverOverlayLayer.presentation()?.opacity ?? hoverOverlayLayer.opacity
        animation.toValue = targetOpacity
        animation.duration = Layout.hoverAnimationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        hoverOverlayLayer.add(animation, forKey: "hoverOpacity")
        hoverOverlayLayer.opacity = targetOpacity
    }
}
