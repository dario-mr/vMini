import AppKit

@MainActor
final class EditorSearchPanel: NSView {
    enum Layout {
        static let fieldHeight: CGFloat = 30
        static let fieldFontSize: CGFloat = 13
        static let countFontSize: CGFloat = 11
        static let iconWidth: CGFloat = 18
        static let buttonHorizontalPadding: CGFloat = 12
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 7
        static let columnSpacing: CGFloat = 8
        static let rowSpacing: CGFloat = 4
        static let rowVerticalPadding: CGFloat = 2
        static let rowHeight = fieldHeight + 2 * rowVerticalPadding
    }

    let searchField = NSTextField()
    let replacementField = NSTextField()
    let countLabel = NSTextField(labelWithString: "")
    let previousButton = EditorSearchButton(symbol: "arrow.up", title: "Previous occurrence", shortcut: "F2")
    let nextButton = EditorSearchButton(symbol: "arrow.down", title: "Next occurrence", shortcut: "F3")
    let closeButton = EditorSearchButton(symbol: "xmark", title: "Close search", shortcut: "Esc")
    let replaceButton = AppButton(title: "Replace", style: .secondary)
    let replaceAllButton = AppButton(title: "Replace All", style: .secondary)
    private let rows = NSStackView()
    private let replacementRow = NSStackView()
    private var panelHeight: NSLayoutConstraint!
    private var rowsHeight: NSLayoutConstraint!

    var showsReplacement: Bool { !replacementRow.isHidden }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isHidden = true
        searchField.setAccessibilityLabel("Find in document")
        searchField.identifier = NSUserInterfaceItemIdentifier("editor.search")
        replacementField.setAccessibilityLabel("Replace with")
        replacementField.identifier = NSUserInterfaceItemIdentifier("editor.replacement")
        for field in [searchField, replacementField] {
            field.cell = EditorSearchFieldCell(textCell: "")
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.isEditable = true
            field.isSelectable = true
            field.cell?.isScrollable = true
            field.controlSize = .large
            field.font = .systemFont(ofSize: Layout.fieldFontSize)
            field.focusRingType = .none
            field.drawsBackground = false
            field.lineBreakMode = .byTruncatingTail
            field.heightAnchor.constraint(equalToConstant: Layout.fieldHeight).isActive = true
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        searchField.placeholderString = "Find in document"
        replacementField.placeholderString = "Replace with"
        countLabel.font = .monospacedDigitSystemFont(ofSize: Layout.countFontSize, weight: .regular)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let searchIcon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        let replaceIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: nil)!)
        for icon in [searchIcon, replaceIcon] {
            icon.widthAnchor.constraint(equalToConstant: Layout.iconWidth).isActive = true
        }
        let searchRow = NSStackView(views: [searchIcon, searchField, countLabel, previousButton, nextButton, closeButton])
        for control in [replaceIcon, replacementField, replaceButton, replaceAllButton] {
            replacementRow.addArrangedSubview(control)
        }
        for button in [replaceButton, replaceAllButton] {
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: ceil(button.attributedTitle.size().width) + 2 * Layout.buttonHorizontalPadding).isActive = true
        }
        replacementRow.isHidden = true
        for row in [searchRow, replacementRow] {
            row.spacing = Layout.columnSpacing
            row.alignment = .centerY
            row.heightAnchor.constraint(equalToConstant: Layout.rowHeight).isActive = true
        }
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = Layout.rowSpacing
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.addArrangedSubview(searchRow)
        rows.addArrangedSubview(replacementRow)
        addSubview(rows)
        panelHeight = heightAnchor.constraint(equalToConstant: 0)
        rowsHeight = rows.heightAnchor.constraint(equalToConstant: Layout.rowHeight)
        NSLayoutConstraint.activate([
            panelHeight,
            rowsHeight,
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            rows.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
            searchRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            replacementRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(replacement: Bool) {
        replacementRow.isHidden = !replacement
        isHidden = false
        rowsHeight.constant = replacement ? 2 * Layout.rowHeight + Layout.rowSpacing : Layout.rowHeight
        panelHeight.constant = rowsHeight.constant + 2 * Layout.verticalInset
    }

    func close() {
        for button in [previousButton, nextButton, closeButton] { button.dismissHint() }
        isHidden = true
        panelHeight.constant = 0
    }

    func updateCount(current: Int?, total: Int) {
        countLabel.stringValue = searchField.stringValue.isEmpty ? "" : total == 0 ? "No matches" : "\(current.map { $0 + 1 } ?? 0) of \(total)"
        previousButton.isEnabled = total > 0
        nextButton.isEnabled = total > 0
        replaceButton.isEnabled = total > 0
        replaceAllButton.isEnabled = total > 0
    }

    func applyTheme() {
        layer?.backgroundColor = AppColors.tabBarBackground.cgColor
        countLabel.textColor = AppColors.inactiveTabText
        for field in [searchField, replacementField] {
            field.textColor = AppColors.primaryText
            field.backgroundColor = .clear
        }
        for button in [previousButton, nextButton, closeButton] {
            button.contentTintColor = AppColors.primaryText
        }
    }
}
