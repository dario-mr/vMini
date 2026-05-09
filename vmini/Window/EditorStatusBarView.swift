import AppKit

struct EditorStatusBarState {
    let title: String
    let autoDetectedSyntaxLanguage: SyntaxLanguage
    let selectedSyntaxLanguage: SyntaxLanguage
    let hasOverride: Bool
}

final class EditorStatusBarView: NSView {
    enum Layout {
        static let preferredHeight: CGFloat = 20
    }

    var onSelectAutomaticSyntaxHighlighting: (() -> Void)?
    var onSelectSyntaxHighlightingOverride: ((SyntaxLanguage) -> Void)?

    private let separatorView = NSView()
    private let syntaxStatusButton = NSButton(title: "", target: nil, action: nil)
    private var state: EditorStatusBarState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        configureSeparator()
        configureButton()
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: EditorStatusBarState?) {
        self.state = state

        guard let state else {
            syntaxStatusButton.title = ""
            syntaxStatusButton.attributedTitle = NSAttributedString(string: "")
            syntaxStatusButton.isEnabled = false
            return
        }

        syntaxStatusButton.isEnabled = true
        syntaxStatusButton.title = state.title
        applyTitleAppearance()
    }

    func applyTheme() {
        layer?.backgroundColor = AppColors.tabBarBackground.blended(withFraction: 0.22, of: AppColors.editorBackground)?.cgColor
            ?? AppColors.tabBarBackground.cgColor
        separatorView.layer?.backgroundColor = AppColors.primaryText.withAlphaComponent(0.08).cgColor
        syntaxStatusButton.contentTintColor = AppColors.defaultControlTint
        applyTitleAppearance()
    }

    private func configureSeparator() {
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.wantsLayer = true
        addSubview(separatorView)

        NSLayoutConstraint.activate([
            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorView.topAnchor.constraint(equalTo: topAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func configureButton() {
        syntaxStatusButton.translatesAutoresizingMaskIntoConstraints = false
        syntaxStatusButton.isBordered = false
        syntaxStatusButton.bezelStyle = .regularSquare
        syntaxStatusButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        syntaxStatusButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Select syntax highlighting")
        syntaxStatusButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        syntaxStatusButton.imagePosition = .imageTrailing
        syntaxStatusButton.target = self
        syntaxStatusButton.action = #selector(showSyntaxHighlightMenu(_:))
        syntaxStatusButton.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(syntaxStatusButton)

        NSLayoutConstraint.activate([
            syntaxStatusButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            syntaxStatusButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func applyTitleAppearance() {
        let attributedTitle = NSAttributedString(
            string: syntaxStatusButton.title,
            attributes: [
                .foregroundColor: AppColors.sidebarText,
                .font: syntaxStatusButton.font as Any,
            ]
        )
        syntaxStatusButton.attributedTitle = attributedTitle
    }

    @objc
    private func showSyntaxHighlightMenu(_ sender: NSButton) {
        guard let state else { return }

        let menu = NSMenu()

        let automaticItem = NSMenuItem(
            title: "\(state.autoDetectedSyntaxLanguage.displayName) (Auto)",
            action: #selector(selectAutomaticSyntaxHighlighting(_:)),
            keyEquivalent: ""
        )
        automaticItem.target = self
        automaticItem.state = state.hasOverride ? .off : .on
        menu.addItem(automaticItem)
        menu.addItem(.separator())

        for language in SyntaxLanguage.allCases {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(selectSyntaxHighlightingOverride(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = state.selectedSyntaxLanguage == language && state.hasOverride ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 2), in: sender)
    }

    @objc
    private func selectAutomaticSyntaxHighlighting(_ sender: NSMenuItem) {
        onSelectAutomaticSyntaxHighlighting?()
    }

    @objc
    private func selectSyntaxHighlightingOverride(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let language = SyntaxLanguage(rawValue: rawValue)
        else {
            return
        }

        onSelectSyntaxHighlightingOverride?(language)
    }
}
