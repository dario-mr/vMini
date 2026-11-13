import AppKit

final class ParquetViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate,
    NSMenuItemValidation {
    private let session: ParquetSession
    private let tableView = ParquetTableView()
    private let scrollView = NSScrollView()
    private let headerView = ParquetTableHeaderView()
    private let toolbar = NSView()
    private let search = ParquetSearchField()
    private var searchFocused = false
    private let clear = AppButton(title: "Clear all", style: .primary)
    private let toolbarDivider = NSView()
    private let searchBox = NSView()
    private let searchIcon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))!)
    private let queryMessage = NSTextField(wrappingLabelWithString: "")
    private var queryMessageHeight: NSLayoutConstraint!
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private lazy var retryButton = NSButton(title: "Retry", target: self, action: #selector(retry))
    private let messageStack = NSStackView()
    private let skeleton = ParquetSkeletonView()
    private var observation: ObservationToken?
    private var themeObservation: ObservationToken?
    private var editorFontObservation: ObservationToken?
    private var cellFont = NSFont.systemFont(ofSize: ParquetTableStyle.Layout.cellFontSize)
    private var page: ParquetPage?
    private var displayedRevision = -1
    private var nearbyColumns = IndexSet()
    var pasteboard = NSPasteboard.general

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
        tableView.style = .plain
        tableView.headerView = headerView
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        tableView.rowHeight = 35
        tableView.setAccessibilityLabel("Read-only Parquet table")
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(refreshRowHover),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        skeleton.tableView = tableView
        view.addSubview(skeleton)
        configureToolbar()
        headerView.onFilterControlsChanged = { [weak self] in self?.updateKeyViewLoop() }
        headerView.onFilterChanged = { [weak self] column, filter, debounce in
            guard let self else { return }
            var query = session.query
            query.filters[column] = filter
            session.apply(query, debounce: debounce)
        }
        queryMessage.translatesAutoresizingMaskIntoConstraints = false
        queryMessage.font = .systemFont(ofSize: ParquetTableStyle.Layout.controlFontSize)
        queryMessage.maximumNumberOfLines = 2
        queryMessage.setAccessibilityLabel("Parquet query message")
        queryMessage.isHidden = true
        view.addSubview(queryMessage)
        queryMessageHeight = queryMessage.heightAnchor.constraint(equalToConstant: 0)

        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 14)
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
            queryMessage.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            queryMessage.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            queryMessage.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            queryMessageHeight,
            scrollView.topAnchor.constraint(equalTo: queryMessage.bottomAnchor),
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
        editorFontObservation = EditorSettings.observe { [weak self] settings in
            guard let self else { return }
            let font = EditorFontResolver.font(for: settings.fontID, size: ParquetTableStyle.Layout.cellFontSize)
            guard font != cellFont else { return }
            cellFont = font
            tableView.reloadData()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Cover the table body only, so the header's sort and filter controls stay usable.
        // The clip view extends under the header (content insets), so measure from the header's bottom edge.
        let headerBottom = view.convert(headerView.bounds, from: headerView).minY
        skeleton.frame = NSRect(x: scrollView.frame.minX, y: scrollView.frame.minY,
                                width: scrollView.frame.width, height: max(0, headerBottom - scrollView.frame.minY))
        headerView.needsLayout = true
        updateNearbyColumns()
    }

    func focusTable() { view.window?.makeFirstResponder(tableView) }

    @objc private func retry() { session.reload(from: session.url) }

    private func configureToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        view.addSubview(toolbar)
        search.stringValue = session.query.search
        search.font = .systemFont(ofSize: ParquetTableStyle.Layout.chromeFontSize)
        (search.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        search.isBezeled = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.onFocusChange = { [weak self] focused in
            self?.searchFocused = focused
            self?.applySearchBorder()
        }
        search.translatesAutoresizingMaskIntoConstraints = false
        searchBox.wantsLayer = true
        searchBox.layer?.cornerRadius = 6
        searchBox.layer?.borderWidth = 1
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.imageScaling = .scaleNone
        searchIcon.imageAlignment = .alignCenter
        searchBox.addSubview(searchIcon)
        searchBox.addSubview(search)
        search.setAccessibilityLabel("Search all Parquet columns")
        search.isEnabled = false
        search.delegate = self
        clear.isEnabled = false
        clear.alphaValue = 0.35
        clear.target = self
        clear.action = #selector(clearFilters)
        let controls = NSStackView(views: [searchBox, clear])
        controls.spacing = 12
        controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(controls)
        toolbarDivider.wantsLayer = true
        toolbarDivider.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(toolbarDivider)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 56),
            controls.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchBox.heightAnchor.constraint(equalToConstant: 32),
            searchIcon.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 16),
            searchIcon.heightAnchor.constraint(equalToConstant: 16),
            search.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 6),
            search.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -6),
            search.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            toolbarDivider.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            toolbarDivider.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            toolbarDivider.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            toolbarDivider.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func update() {
        let schemaChanged = page?.columns != session.page?.columns
        page = session.page
        if schemaChanged { configureColumns() }
        progressIndicator.stopAnimation(nil)
        retryButton.isHidden = true
        messageStack.isHidden = page != nil
        scrollView.isHidden = page == nil
        queryMessage.stringValue = ""
        queryMessage.isHidden = true
        queryMessageHeight.constant = 0
        queryMessage.textColor = .systemRed
        var isLoading = false
        switch session.state {
        case .loading:
            isLoading = true
            messageLabel.stringValue = "Loading Parquet…"
            progressIndicator.startAnimation(nil)
        case .failed(let message):
            if page != nil {
                showQueryMessage("\(message) Last valid results are shown.")
            } else {
                messageLabel.stringValue = "Could not open Parquet file.\n\(message)"
                retryButton.isHidden = false
            }
        case .closed:
            messageLabel.stringValue = ""
        case .loaded(let page):
            if page.didResetQuery {
                headerView.update(query: session.query, resetControls: true)
                queryMessage.textColor = .systemOrange
                showQueryMessage("The file schema changed. Unavailable sorts and filters were cleared.")
            }
            messageLabel.stringValue = page.query.isFiltered ? "No rows" : "This Parquet file has no rows."
            messageStack.isHidden = !page.rows.isEmpty
        }
        skeleton.setActive(isLoading && page != nil)
        // Without rows, hide the empty grid so only the message shows under the header.
        tableView.gridStyleMask = page?.rows.isEmpty == false ? [.solidVerticalGridLineMask, .solidHorizontalGridLineMask] : []
        search.isEnabled = page != nil
        clear.isEnabled = session.query.isFiltered
        clear.alphaValue = clear.isEnabled ? 1 : 0.35
        headerView.update(query: session.query)
        if displayedRevision != session.resultRevision {
            displayedRevision = session.resultRevision
            tableView.deselectAll(nil)
            updateNearbyColumns(reload: false)
            tableView.reloadData()
            if tableView.numberOfRows > 0 { tableView.scrollRowToVisible(0) }
        }
    }

    private func configureColumns() {
        tableView.tableColumns.forEach(tableView.removeTableColumn)
        headerView.configure(columns: [])
        guard let page else { return }
        let rowNumber = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rowNumber"))
        rowNumber.headerCell = ParquetTableHeaderCell(textCell: "#")
        rowNumber.headerCell.alignment = .center
        rowNumber.isEditable = false
        rowNumber.width = 52
        rowNumber.minWidth = 52
        rowNumber.maxWidth = 52
        rowNumber.resizingMask = []
        tableView.addTableColumn(rowNumber)
        for (index, column) in page.columns.enumerated() {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            let headerCell = ParquetTableHeaderCell(textCell: column.name)
            headerCell.typeName = column.type
            tableColumn.headerCell = headerCell
            tableColumn.isEditable = false
            tableColumn.minWidth = 150
            tableColumn.maxWidth = 800
            let kind = ParquetColumnKind(type: column.type)
            let width: CGFloat = kind == .date ? 220 : kind == .text ? 185 : kind == .boolean ? 150 : 160
            tableColumn.width = min(320, max(width, CGFloat(tableColumn.title.count) * 7 + 24))
            tableColumn.resizingMask = .userResizingMask
            tableView.addTableColumn(tableColumn)
        }
        headerView.configure(columns: page.columns, query: session.query)
        updateKeyViewLoop()
    }

    // Programmatic views get no Tab order, so link search → column filters → table → search.
    private func updateKeyViewLoop() {
        let keyViews: [NSView] = [search] + headerView.filterControls + [tableView]
        for (view, next) in zip(keyViews, keyViews.dropFirst() + [search]) { view.nextKeyView = next }
    }

    private func showQueryMessage(_ message: String) {
        queryMessage.stringValue = message
        queryMessage.toolTip = message
        queryMessage.isHidden = false
        queryMessageHeight.constant = 36
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === search else { return }
        var query = session.query
        query.search = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        session.apply(query, debounce: true)
    }

    @objc private func clearFilters() {
        view.window?.makeFirstResponder(tableView)
        search.stringValue = ""
        session.clearFilters()
        headerView.update(query: session.query, resetControls: true)
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let page, let index = Int(tableColumn.identifier.rawValue) else { return }
        session.cycleSort(column: page.columns[index])
    }

    private func applySearchBorder() {
        searchBox.layer?.borderColor = (searchFocused ? ParquetTableStyle.focusBorder : ParquetTableStyle.searchBorder).cgColor
    }

    private func applyTheme() {
        view.layer?.backgroundColor = AppColors.editorBackground.cgColor
        scrollView.backgroundColor = AppColors.editorBackground
        tableView.backgroundColor = AppColors.editorBackground
        tableView.gridColor = ParquetTableStyle.grid
        toolbar.layer?.backgroundColor = ParquetTableStyle.filter.cgColor
        toolbarDivider.layer?.backgroundColor = ParquetTableStyle.grid.cgColor
        searchBox.layer?.backgroundColor = ParquetTableStyle.searchFill.cgColor
        applySearchBorder()
        searchIcon.contentTintColor = ParquetTableStyle.mutedText
        search.textColor = AppColors.primaryText
        search.placeholderAttributedString = NSAttributedString(string: "Search all", attributes: [
            .foregroundColor: ParquetTableStyle.mutedText, .font: search.font as Any,
        ])
        headerView.applyTheme()
        view.appearance = NSAppearance(named: AppColors.editorBackground.brightnessComponent < 0.5 ? .darkAqua : .aqua)
        messageLabel.textColor = AppColors.primaryText
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { page?.rows.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let page, let tableColumn, nearbyColumns.contains(tableView.column(withIdentifier: tableColumn.identifier)) else { return nil }
        let isRowNumber = tableColumn.identifier.rawValue == "rowNumber"
        let identifier = NSUserInterfaceItemIdentifier(isRowNumber ? "ParquetRowNumberCell" : "ParquetCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCellView(identifier: identifier, inset: isRowNumber ? ParquetTableStyle.Layout.rowNumberInset : ParquetTableStyle.Layout.cellInset)
        guard let textField = cell.textField else { return nil }
        guard let index = Int(tableColumn.identifier.rawValue) else {
            textField.stringValue = (row + 1).localizedCount
            textField.alignment = .center
            textField.font = .monospacedDigitSystemFont(ofSize: ParquetTableStyle.Layout.cellFontSize - 1, weight: .regular)
            textField.textColor = ParquetTableStyle.mutedText
            textField.setAccessibilityLabel("Row \(row + 1)")
            return cell
        }
        let value = page.rows[row][index]
        let kind = ParquetColumnKind(type: page.columns[index].type)
        // shortcut: cap display text at 500 characters; add full-value inspection with advanced formatting.
        textField.stringValue = value.map { String($0.prefix(500)) } ?? "NULL"
        textField.font = value == nil ? NSFontManager.shared.convert(cellFont, toHaveTrait: .italicFontMask) : cellFont
        textField.alignment = kind == .number ? .right : .left
        textField.textColor = value == nil ? ParquetTableStyle.mutedText : AppColors.primaryText
        if kind == .boolean, let value {
            textField.textColor = (value == "true" ? NSColor.systemGreen : NSColor.systemPink)
                .blended(withFraction: 0.45, of: AppColors.primaryText)
        }
        textField.setAccessibilityLabel(value == nil ? "NULL, missing value" : textField.stringValue)
        return cell
    }

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier, inset: CGFloat) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        // Per-cell toolTips add tracking areas that AppKit rebuilds on every scroll frame.
        textField.allowsExpansionToolTips = true
        cell.textField = textField
        cell.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -inset),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool { false }

    /// Copies the selected rectangle as tab-separated rows; NULL copies as empty text.
    @objc func copy(_ sender: Any?) {
        guard let page, let selection = tableView.cellSelection else { return }
        let columns = selection.columns.filter(tableView.tableColumns.indices.contains).map { Int(tableView.tableColumns[$0].identifier.rawValue) }
        let lines = selection.rows.filter(page.rows.indices.contains).map { row in
            columns.map { index in index.map { page.rows[row][$0] ?? "" } ?? String(row + 1) }.joined(separator: "\t")
        }
        guard !lines.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(copy(_:)) ? page != nil && tableView.cellSelection != nil : true
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("ParquetRow")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? ParquetTableRowView ?? ParquetTableRowView()
        view.identifier = identifier
        view.alternate = !row.isMultiple(of: 2)
        view.needsDisplay = true
        return view
    }

    func tableViewColumnDidResize(_ notification: Notification) { tableView.refreshCellSelection(); headerView.needsLayout = true; skeleton.needsDisplay = true; updateNearbyColumns() }
    func tableViewColumnDidMove(_ notification: Notification) { tableView.refreshCellSelection(); headerView.needsLayout = true; skeleton.needsDisplay = true; updateNearbyColumns() }

    // Perf: realize only nearby columns and reload columns as they come into range.
    private func updateNearbyColumns(reload: Bool = true) {
        let visible = scrollView.contentView.bounds
        let width = visible.width > 0 ? visible.width : 1_000  // Before the first layout, assume a typical viewport.
        let nearby = NSRect(x: visible.minX - width, y: 0, width: width * 3, height: max(1, tableView.bounds.height))
        let current = tableView.columnIndexes(in: nearby)
        guard current != nearbyColumns else { return }
        let changed = current.symmetricDifference(nearbyColumns).filteredIndexSet { $0 < tableView.numberOfColumns }
        nearbyColumns = current
        guard reload else { return }
        var rows = IndexSet()
        tableView.enumerateAvailableRowViews { _, row in rows.insert(row) }
        if !rows.isEmpty { tableView.reloadData(forRowIndexes: rows, columnIndexes: changed) }
    }

    @objc private func refreshRowHover() {
        skeleton.needsDisplay = true
        headerView.needsLayout = true
        updateNearbyColumns()
        tableView.enumerateAvailableRowViews { row, _ in
            (row as? ParquetTableRowView)?.refreshHover()
        }
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
