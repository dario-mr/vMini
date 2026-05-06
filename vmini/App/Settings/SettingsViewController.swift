import AppKit

@MainActor
final class SettingsViewController: NSViewController {
    private enum Layout {
        static let minimumWidth: CGFloat = 420
        static let horizontalInset: CGFloat = 24
        static let topInset: CGFloat = 20
        static let bottomInset: CGFloat = 20
        static let titleToRowSpacing: CGFloat = 20
        static let rowToButtonSpacing: CGFloat = 24
        static let rowHeight: CGFloat = 28
        static let buttonMinimumWidth: CGFloat = 68
        static let buttonHeight: CGFloat = 28
        static let buttonCornerRadius: CGFloat = 7
    }

    var onDone: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Settings")
    private let themeSelectionRowView = ThemeSelectionRowView()
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    init() {
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: Layout.minimumWidth, height: 160)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true

        configureTitleLabel()
        configureDoneButton()

        themeSelectionRowView.onThemeSelected = { themeID in
            ThemeManager.shared.setThemeID(themeID)
        }

        view.addSubview(titleLabel)
        view.addSubview(themeSelectionRowView)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumWidth),

            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.topInset),

            themeSelectionRowView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            themeSelectionRowView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            themeSelectionRowView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Layout.titleToRowSpacing),
            themeSelectionRowView.heightAnchor.constraint(equalToConstant: Layout.rowHeight),

            doneButton.topAnchor.constraint(equalTo: themeSelectionRowView.bottomAnchor, constant: Layout.rowToButtonSpacing),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.buttonMinimumWidth),
            doneButton.heightAnchor.constraint(equalToConstant: Layout.buttonHeight),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            doneButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.bottomInset),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyTheme()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureTitleLabel() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    }

    private func configureDoneButton() {
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.target = self
        doneButton.action = #selector(handleDoneButton)
        doneButton.isBordered = false
        doneButton.wantsLayer = true
        doneButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        doneButton.contentTintColor = nil
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        doneButton.keyEquivalent = "\r"
    }

    private func applyTheme() {
        view.layer?.backgroundColor = AppColors.windowBackground.cgColor
        titleLabel.textColor = AppColors.primaryText
        doneButton.layer?.backgroundColor = AppColors.primaryActionBackground.cgColor
        doneButton.layer?.cornerRadius = Layout.buttonCornerRadius
        doneButton.attributedTitle = NSAttributedString(
            string: doneButton.title,
            attributes: [.foregroundColor: AppColors.primaryActionText]
        )
        doneButton.attributedAlternateTitle = NSAttributedString(
            string: doneButton.title,
            attributes: [.foregroundColor: AppColors.primaryActionText]
        )
    }

    private func updatePreferredContentSize() {
        let fittingSize = view.fittingSize
        let measuredSize = NSSize(
            width: max(Layout.minimumWidth, fittingSize.width),
            height: fittingSize.height
        )

        guard preferredContentSize != measuredSize else {
            return
        }

        preferredContentSize = measuredSize
        view.window?.setContentSize(measuredSize)
    }

    @objc
    private func handleDoneButton() {
        onDone?()
    }

    @objc
    private func handleThemeDidChange() {
        applyTheme()
    }

    override func cancelOperation(_ sender: Any?) {
        onDone?()
    }
}
