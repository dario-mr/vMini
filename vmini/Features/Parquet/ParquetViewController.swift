import AppKit

final class ParquetViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let session: ParquetSession
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private lazy var retryButton = NSButton(title: "Retry", target: self, action: #selector(retry))
    private let messageStack = NSStackView()
    private var observation: ObservationToken?
    private var themeObservation: ObservationToken?
    private var page: ParquetPage?

    init(session: ParquetSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.setAccessibilityLabel("Read-only Parquet table")
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 8
        messageStack.orientation = .vertical
        messageStack.alignment = .centerX
        messageStack.spacing = 12
        [progressIndicator, messageLabel, retryButton].forEach(messageStack.addArrangedSubview)
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            messageStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageStack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observation = session.observe { [weak self] in self?.update() }
        themeObservation = ThemeManager.shared.observe { [weak self] _ in self?.applyTheme() }
    }

    func focusTable() { view.window?.makeFirstResponder(tableView) }

    @objc private func retry() { session.reload(from: session.url) }

    private func update() {
        page = nil
        tableView.tableColumns.forEach(tableView.removeTableColumn)
        progressIndicator.stopAnimation(nil)
        retryButton.isHidden = true
        messageStack.isHidden = false
        switch session.state {
        case .loading:
            messageLabel.stringValue = "Loading Parquet…"
            progressIndicator.startAnimation(nil)
        case .failed(let message):
            messageLabel.stringValue = "Could not open Parquet file.\n\(message)"
            retryButton.isHidden = false
        case .closed:
            messageLabel.stringValue = ""
        case .loaded(let page):
            self.page = page
            for (index, column) in page.columns.enumerated() {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
                tableColumn.title = column.name
                tableColumn.headerToolTip = "\(column.name) (\(column.type))"
                tableColumn.isEditable = false
                tableColumn.minWidth = 60
                tableColumn.maxWidth = 800
                tableColumn.width = min(320, max(160, CGFloat(tableColumn.title.count) * 7))
                tableColumn.resizingMask = .userResizingMask
                tableView.addTableColumn(tableColumn)
            }
            messageLabel.stringValue = "This Parquet file has no rows."
            messageStack.isHidden = !page.rows.isEmpty
        }
        tableView.reloadData()
    }

    private func applyTheme() {
        view.layer?.backgroundColor = AppColors.editorBackground.cgColor
        scrollView.backgroundColor = AppColors.editorBackground
        tableView.backgroundColor = AppColors.editorBackground
        view.appearance = NSAppearance(named: AppColors.editorBackground.brightnessComponent < 0.5 ? .darkAqua : .aqua)
        messageLabel.textColor = AppColors.primaryText
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { page?.rows.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let page, let tableColumn, let index = Int(tableColumn.identifier.rawValue) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ParquetCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCellView(identifier: identifier)
        guard let textField = cell.textField else { return nil }
        let value = page.rows[row][index]
        // shortcut: cap display/tooltip text at 500/4,000 characters; add full-value inspection with advanced formatting.
        textField.stringValue = value.map { String($0.prefix(500)) } ?? "NULL"
        cell.toolTip = value.map { String($0.prefix(4_000)) } ?? "NULL (missing value)"
        textField.font = value == nil ? NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
            : .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.textColor = value == nil ? AppColors.primaryText.withAlphaComponent(0.55) : AppColors.primaryText
        textField.setAccessibilityLabel(value == nil ? "NULL, missing value" : textField.stringValue)
        return cell
    }

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.alignment = .center
        cell.textField = textField
        cell.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool { false }
}
