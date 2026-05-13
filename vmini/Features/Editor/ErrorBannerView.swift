import AppKit

@MainActor
final class ErrorBannerView: NSView {
    private enum Constants {
        static let height: CGFloat = 30
        static let minimumWidth: CGFloat = 180
        static let horizontalInset: CGFloat = 12
        static let verticalGap: CGFloat = 6
        static let maximumWidth: CGFloat = 560
    }

    var onDismiss: (() -> Void)?

    var message: String? {
        didSet {
            label.stringValue = message ?? ""
            isHidden = (message == nil)
        }
    }

    private let label = NSTextField(labelWithString: "")
    private let dismissButton = NSButton(title: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
        label.textColor = NSColor.systemRed.blended(withFraction: 0.8, of: AppColors.primaryText) ?? AppColors.primaryText
        dismissButton.contentTintColor = label.textColor
    }

    func updateFrame(
        in clipView: NSClipView,
        window: NSWindow,
        textView: NSTextView,
        characterLocation: Int
    ) {
        guard let message else {
            return
        }

        label.stringValue = message

        let viewportWidth = clipView.bounds.width
        let bannerWidth = max(
            min(viewportWidth - (Constants.horizontalInset * 2), Constants.maximumWidth),
            Constants.minimumWidth
        )
        let linePoint = pointForBanner(
            in: clipView,
            window: window,
            textView: textView,
            characterLocation: characterLocation
        )
        let x = min(
            max(linePoint.x, Constants.horizontalInset),
            max(Constants.horizontalInset, viewportWidth - bannerWidth - Constants.horizontalInset)
        )
        let y = bannerYPosition(for: linePoint, in: clipView)

        frame = NSRect(x: x, y: y, width: bannerWidth, height: Constants.height)
    }

    private func configureView() {
        wantsLayer = true
        isHidden = true
        frame = NSRect(x: 0, y: 0, width: Constants.minimumWidth, height: Constants.height)
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.isBordered = false
        dismissButton.bezelStyle = .regularSquare
        dismissButton.imagePosition = .imageOnly
        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss formatting error")
        dismissButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        dismissButton.target = self
        dismissButton.action = #selector(handleDismissButton(_:))

        addSubview(label)
        addSubview(dismissButton)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 18),
            dismissButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func pointForBanner(
        in clipView: NSClipView,
        window: NSWindow,
        textView: NSTextView,
        characterLocation: Int
    ) -> NSPoint {
        let textLength = textView.string.utf16.count
        let targetLocation = min(max(characterLocation, 0), textLength)
        let characterRange = NSRange(location: targetLocation, length: 0)

        let rectInScreen = textView.firstRect(forCharacterRange: characterRange, actualRange: nil)
        let rectInWindow = window.convertFromScreen(rectInScreen)
        return clipView.convert(rectInWindow.origin, from: nil)
    }

    private func bannerYPosition(for linePoint: NSPoint, in clipView: NSClipView) -> CGFloat {
        let topInset = Constants.verticalGap
        let bottomInset = Constants.verticalGap
        let maxY = clipView.bounds.height - Constants.height - bottomInset

        if clipView.isFlipped {
            return min(
                max(topInset, linePoint.y - Constants.height - Constants.verticalGap),
                maxY
            )
        }

        return max(
            bottomInset,
            min(maxY, linePoint.y + Constants.verticalGap)
        )
    }

    @objc
    private func handleDismissButton(_ sender: Any?) {
        onDismiss?()
    }
}
