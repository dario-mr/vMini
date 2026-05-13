import AppKit

@MainActor
final class FontSizeHUDView: NSView {
    private enum Layout {
        static let horizontalInset: CGFloat = 14
        static let verticalInset: CGFloat = 8
        static let cornerRadius: CGFloat = 10
        static let textSize: CGFloat = 13
        static let minimumWidth: CGFloat = 75
        static let displayDuration: TimeInterval = 1
        static let fadeDuration: TimeInterval = 0.16
    }

    private let label = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?
    private var themeObservation: ObservationToken?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        alphaValue = 0
        isHidden = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: Layout.textSize, weight: .semibold)
        label.alignment = .center
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumWidth),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalInset),
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

    func show(fontSize: CGFloat) {
        label.stringValue = formatted(fontSize: fontSize)
        hideWorkItem?.cancel()
        isHidden = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.fadeDuration
            animator().alphaValue = 1
        }

        let hideWorkItem = DispatchWorkItem { [weak self] in
            self?.hideAnimated()
        }
        self.hideWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.displayDuration, execute: hideWorkItem)
    }

    func applyTheme() {
        layer?.cornerRadius = Layout.cornerRadius
        layer?.masksToBounds = true
        layer?.backgroundColor = AppColors.tabBarBackground
            .blended(withFraction: 0.4, of: AppColors.editorBackground)?
            .withAlphaComponent(0.96)
            .cgColor ?? AppColors.tabBarBackground.cgColor
        label.textColor = AppColors.primaryText
    }

    private func hideAnimated() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Layout.fadeDuration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.isHidden = true
            }
        })
    }

    private func formatted(fontSize: CGFloat) -> String {
        if fontSize.rounded(.towardZero) == fontSize {
            return "\(Int(fontSize)) pt"
        }

        return String(format: "%.1f pt", fontSize)
    }
}
