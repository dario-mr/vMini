import AppKit

@MainActor
final class ThemeSelectionRowView: NSView {
    var onThemeSelected: ((ThemeID) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Theme")
    private let themePopUpButton = NSPopUpButton()
    private var themeObservation: ObservationToken?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        configureTitleLabel()
        configurePopUpButton()

        addSubview(titleLabel)
        addSubview(themePopUpButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            themePopUpButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),
            themePopUpButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            themePopUpButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            themePopUpButton.widthAnchor.constraint(equalToConstant: 180),
        ])

        applyTheme()
        reloadThemeOptions()

        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.handleThemeDidChange()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureTitleLabel() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    }

    private func configurePopUpButton() {
        themePopUpButton.translatesAutoresizingMaskIntoConstraints = false
        themePopUpButton.target = self
        themePopUpButton.action = #selector(handleThemeSelectionChanged(_:))
    }

    private func applyTheme() {
        titleLabel.textColor = AppColors.primaryText
        themePopUpButton.contentTintColor = AppColors.primaryText
    }

    private func reloadThemeOptions() {
        themePopUpButton.removeAllItems()
        for themeID in ThemeID.allCases {
            themePopUpButton.addItem(withTitle: themeID.displayName)
            themePopUpButton.lastItem?.representedObject = themeID
        }

        if let selectedIndex = ThemeID.allCases.firstIndex(of: ThemeManager.shared.selectedThemeID) {
            themePopUpButton.selectItem(at: selectedIndex)
        }
    }

    @objc
    private func handleThemeSelectionChanged(_ sender: NSPopUpButton) {
        guard let themeID = sender.selectedItem?.representedObject as? ThemeID else {
            return
        }

        onThemeSelected?(themeID)
    }

    private func handleThemeDidChange() {
        applyTheme()
        reloadThemeOptions()
    }
}
