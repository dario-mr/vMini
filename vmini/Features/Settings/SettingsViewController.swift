import AppKit

@MainActor
final class SettingsViewController: NSViewController {
    private enum Layout {
        static let minimumWidth: CGFloat = 420
        static let horizontalInset: CGFloat = 24
        static let topInset: CGFloat = 20
        static let bottomInset: CGFloat = 20
        static let titleToRowSpacing: CGFloat = 20
        static let rowSpacing: CGFloat = 14
        static let rowToButtonSpacing: CGFloat = 24
        static let rowHeight: CGFloat = 28
    }

    var onDone: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Settings")
    private let themeSelectionRowView = ThemeSelectionRowView()
    private let fontSelectionRowView = FontSelectionRowView()
    private let doneButton = AppButton(title: "Done", style: .primary)
    private var themeObservation: ObservationToken?

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
        fontSelectionRowView.onFontSelected = { fontID in
            EditorSettings.setFontID(fontID)
        }

        view.addSubview(titleLabel)
        view.addSubview(themeSelectionRowView)
        view.addSubview(fontSelectionRowView)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumWidth),

            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.topInset),

            themeSelectionRowView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            themeSelectionRowView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            themeSelectionRowView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Layout.titleToRowSpacing),
            themeSelectionRowView.heightAnchor.constraint(equalToConstant: Layout.rowHeight),

            fontSelectionRowView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            fontSelectionRowView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            fontSelectionRowView.topAnchor.constraint(equalTo: themeSelectionRowView.bottomAnchor, constant: Layout.rowSpacing),
            fontSelectionRowView.heightAnchor.constraint(equalToConstant: Layout.rowHeight),

            doneButton.topAnchor.constraint(equalTo: fontSelectionRowView.bottomAnchor, constant: Layout.rowToButtonSpacing),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            doneButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.bottomInset),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.applyTheme()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    private func configureTitleLabel() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    }

    private func configureDoneButton() {
        doneButton.target = self
        doneButton.action = #selector(handleDoneButton)
        doneButton.keyEquivalent = "\r"
    }

    private func applyTheme() {
        view.layer?.backgroundColor = AppColors.windowBackground.cgColor
        titleLabel.textColor = AppColors.primaryText
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
    override func cancelOperation(_ sender: Any?) {
        onDone?()
    }
}
