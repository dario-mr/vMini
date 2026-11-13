import AppKit

/// The search box and Clear button above the Parquet table.
final class ParquetToolbarView: NSView, NSSearchFieldDelegate {
    var onSearchChanged: ((String) -> Void)?
    var onClear: (() -> Void)?

    let searchField = ParquetSearchField()
    private var searchFocused = false
    private let clearButton = AppButton(title: "Clear all", style: .primary)
    private let divider = NSView()
    private let searchBox = NSView()
    private let searchIcon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))!)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        searchField.font = .systemFont(ofSize: ParquetTableStyle.Layout.chromeFontSize)
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.onFocusChange = { [weak self] focused in
            self?.searchFocused = focused
            self?.applySearchBorder()
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchBox.wantsLayer = true
        searchBox.layer?.cornerRadius = 6
        searchBox.layer?.borderWidth = 1
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.imageScaling = .scaleNone
        searchIcon.imageAlignment = .alignCenter
        searchBox.addSubview(searchIcon)
        searchBox.addSubview(searchField)
        searchField.setAccessibilityLabel("Search all Parquet columns")
        searchField.isEnabled = false
        searchField.delegate = self
        setClearEnabled(false)
        clearButton.target = self
        clearButton.action = #selector(clear)
        let controls = NSStackView(views: [searchBox, clearButton])
        controls.spacing = 12
        controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controls)
        divider.wantsLayer = true
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchBox.heightAnchor.constraint(equalToConstant: 32),
            searchIcon.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 16),
            searchIcon.heightAnchor.constraint(equalToConstant: 16),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -6),
            searchField.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setClearEnabled(_ isEnabled: Bool) {
        clearButton.isEnabled = isEnabled
        clearButton.alphaValue = isEnabled ? 1 : 0.35
    }

    func applyTheme() {
        layer?.backgroundColor = ParquetTableStyle.filter.cgColor
        divider.layer?.backgroundColor = ParquetTableStyle.grid.cgColor
        searchBox.layer?.backgroundColor = ParquetTableStyle.searchFill.cgColor
        applySearchBorder()
        searchIcon.contentTintColor = ParquetTableStyle.mutedText
        searchField.textColor = AppColors.primaryText
        searchField.placeholderAttributedString = NSAttributedString(string: "Search all", attributes: [
            .foregroundColor: ParquetTableStyle.mutedText, .font: searchField.font as Any,
        ])
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        onSearchChanged?(searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc private func clear() { onClear?() }

    private func applySearchBorder() {
        searchBox.layer?.borderColor = (searchFocused ? ParquetTableStyle.focusBorder : ParquetTableStyle.searchBorder).cgColor
    }
}

final class ParquetSearchField: NSSearchField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}
