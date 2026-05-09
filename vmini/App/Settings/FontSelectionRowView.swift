import AppKit

@MainActor
final class FontSelectionRowView: NSView {
    var onFontSelected: ((EditorFontID) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Editor Font")
    private let fontPopUpButton = NSPopUpButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        configureTitleLabel()
        configurePopUpButton()

        addSubview(titleLabel)
        addSubview(fontPopUpButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            fontPopUpButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),
            fontPopUpButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            fontPopUpButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            fontPopUpButton.widthAnchor.constraint(equalToConstant: 180),
        ])

        applyTheme()
        reloadFontOptions()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEditorAppearanceDidChange),
            name: EditorSettings.appearanceDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureTitleLabel() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    }

    private func configurePopUpButton() {
        fontPopUpButton.translatesAutoresizingMaskIntoConstraints = false
        fontPopUpButton.target = self
        fontPopUpButton.action = #selector(handleFontSelectionChanged(_:))
    }

    private func applyTheme() {
        titleLabel.textColor = AppColors.primaryText
        fontPopUpButton.contentTintColor = AppColors.primaryText
    }

    private func reloadFontOptions() {
        let availableFonts = EditorFontResolver.availableFontIDs()
        fontPopUpButton.removeAllItems()

        for fontID in availableFonts {
            fontPopUpButton.addItem(withTitle: fontID.displayName)
            fontPopUpButton.lastItem?.representedObject = fontID
        }

        if let selectedIndex = availableFonts.firstIndex(of: EditorSettings.currentFontID()) {
            fontPopUpButton.selectItem(at: selectedIndex)
        }
    }

    @objc
    private func handleFontSelectionChanged(_ sender: NSPopUpButton) {
        guard let fontID = sender.selectedItem?.representedObject as? EditorFontID else {
            return
        }

        onFontSelected?(fontID)
    }

    @objc
    private func handleThemeDidChange() {
        applyTheme()
    }

    @objc
    private func handleEditorAppearanceDidChange() {
        reloadFontOptions()
    }
}
