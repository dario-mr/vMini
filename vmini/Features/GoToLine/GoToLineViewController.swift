import AppKit

@MainActor
final class GoToLineViewController: NSViewController {
    private enum Layout {
        static let minimumWidth: CGFloat = 360
        static let horizontalInset: CGFloat = 24
        static let topInset: CGFloat = 20
        static let bottomInset: CGFloat = 20
        static let titleToFieldSpacing: CGFloat = 16
        static let fieldToButtonSpacing: CGFloat = 24
        static let textFieldHeight: CGFloat = 28
        static let buttonSpacing: CGFloat = 10
    }

    var onGoToLine: ((Int) -> Void)?
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Go to Line")
    private let lineNumberField = NSTextField()
    private let buttonStackView = NSStackView()
    private let cancelButton = AppButton(title: "Cancel", style: .secondary)
    private let goButton = AppButton(title: "Go", style: .primary)
    private var themeObservation: ObservationToken?

    init() {
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: Layout.minimumWidth, height: 132)
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
        configureLineNumberField()
        configureButtonStackView()
        configureButtons()

        view.addSubview(titleLabel)
        view.addSubview(lineNumberField)
        view.addSubview(buttonStackView)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumWidth),

            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.topInset),

            lineNumberField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            lineNumberField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            lineNumberField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Layout.titleToFieldSpacing),
            lineNumberField.heightAnchor.constraint(equalToConstant: Layout.textFieldHeight),

            buttonStackView.topAnchor.constraint(equalTo: lineNumberField.bottomAnchor, constant: Layout.fieldToButtonSpacing),
            buttonStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            buttonStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.bottomInset),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.applyTheme()
        }
    }

    func configure(currentLineNumber: Int) {
        lineNumberField.stringValue = "\(currentLineNumber)"
        if isViewLoaded {
            lineNumberField.selectText(nil)
        }
    }

    func focusLineNumberField() {
        view.window?.makeFirstResponder(lineNumberField)
        lineNumberField.selectText(nil)
    }

    private func configureTitleLabel() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    }

    private func configureLineNumberField() {
        lineNumberField.translatesAutoresizingMaskIntoConstraints = false
        lineNumberField.placeholderString = "Line number"
        lineNumberField.font = NSFont.systemFont(ofSize: 13)
    }

    private func configureButtonStackView() {
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.orientation = .horizontal
        buttonStackView.alignment = .centerY
        buttonStackView.spacing = Layout.buttonSpacing
        buttonStackView.addArrangedSubview(cancelButton)
        buttonStackView.addArrangedSubview(goButton)
    }

    private func configureButtons() {
        cancelButton.target = self
        cancelButton.action = #selector(handleCancelButton)
        cancelButton.keyEquivalent = "\u{1b}"

        goButton.target = self
        goButton.action = #selector(handleGoButton)
        goButton.keyEquivalent = "\r"
    }

    private func applyTheme() {
        view.layer?.backgroundColor = AppColors.windowBackground.cgColor
        titleLabel.textColor = AppColors.primaryText
        lineNumberField.textColor = AppColors.primaryText
        lineNumberField.backgroundColor = AppColors.editorBackground
    }

    private func submit() {
        let trimmed = lineNumberField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lineNumber = Int(trimmed), lineNumber > 0 else {
            NSSound.beep()
            focusLineNumberField()
            return
        }

        onGoToLine?(lineNumber)
    }

    @objc
    private func handleCancelButton() {
        onCancel?()
    }

    @objc
    private func handleGoButton() {
        submit()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
