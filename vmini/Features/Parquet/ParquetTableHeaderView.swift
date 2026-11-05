import AppKit

final class ParquetTableHeaderView: NSTableHeaderView {
    static let titleHeight: CGFloat = 52
    static let filterHeight = ParquetTableStyle.Layout.filterControlHeight + 2 * ParquetTableStyle.Layout.filterRowPadding
    private var columns: [ParquetPage.Column] = []
    private var query = ParquetQuery()
    private var filters: [Int: ParquetColumnFilterView] = [:]
    var onFilterChanged: ((ParquetPage.Column, ParquetQuery.Filter?, Bool) -> Void)?
    var onFilterControlsChanged: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.titleHeight + Self.filterHeight))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(columns: [ParquetPage.Column], query: ParquetQuery = ParquetQuery()) {
        filters.values.forEach { $0.removeFromSuperview() }
        filters = [:]
        self.columns = columns
        self.query = query
        needsLayout = true
    }

    func update(query: ParquetQuery, resetControls: Bool = false) {
        self.query = query
        guard let tableView else { return }
        if resetControls { filters.values.forEach { $0.reset(filter: query.filters[$0.column]) } }
        for tableColumn in tableView.tableColumns {
            guard let index = Int(tableColumn.identifier.rawValue), columns.indices.contains(index),
                  let cell = tableColumn.headerCell as? ParquetTableHeaderCell else { continue }
            let column = columns[index]
            cell.sortAscending = query.sort?.column == column ? query.sort?.ascending : nil
            cell.filterActive = query.filters[column] != nil
        }
        let sorting = query.sort.map { "Sorted by \($0.column.name), \($0.ascending ? "ascending" : "descending")." } ?? "Unsorted."
        setAccessibilityLabel("Parquet column headers. \(sorting)")
        needsDisplay = true
    }

    var filterControls: [NSView] {
        (tableView?.tableColumns ?? []).compactMap { Int($0.identifier.rawValue).flatMap { filters[$0] } }.flatMap(\.subviews)
    }

    func applyTheme() { needsDisplay = true }

    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + filterControls
    }

    // Perf: filter controls exist only near the visible columns.
    override func layout() {
        super.layout()
        guard let tableView, let visible = tableView.enclosingScrollView?.contentView.bounds else { return }
        let nearby = visible.insetBy(dx: -visible.width, dy: 0)
        var changed = false
        for (tableIndex, tableColumn) in tableView.tableColumns.enumerated() {
            guard let index = Int(tableColumn.identifier.rawValue), columns.indices.contains(index) else { continue }
            let rect = headerRect(ofColumn: tableIndex)
            if rect.width > 0, rect.maxX >= nearby.minX, rect.minX <= nearby.maxX {
                let filter = filters[index] ?? makeFilter(index)
                if filter.superview == nil { addSubview(filter); changed = true }
                filter.frame = NSRect(x: rect.minX + 5, y: Self.titleHeight + ParquetTableStyle.Layout.filterRowPadding,
                                      width: max(0, rect.width - 10), height: ParquetTableStyle.Layout.filterControlHeight)
            } else if let filter = filters[index], !holdsFocus(filter) {
                filter.removeFromSuperview()
                filters[index] = nil
                changed = true
            }
        }
        if changed { onFilterControlsChanged?() }
    }

    private func makeFilter(_ index: Int) -> ParquetColumnFilterView {
        let column = columns[index]
        let filter = ParquetColumnFilterView(column: column, filter: query.filters[column])
        filter.onChange = { [weak self] value, debounce in self?.onFilterChanged?(column, value, debounce) }
        filter.identifier = NSUserInterfaceItemIdentifier(String(index))
        filters[index] = filter
        return filter
    }

    private func holdsFocus(_ filter: NSView) -> Bool {
        (window?.firstResponder as? NSView)?.isDescendant(of: filter) == true
    }

    override func draw(_ dirtyRect: NSRect) {
        ParquetTableStyle.header.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}

final class ParquetTableHeaderCell: NSTableHeaderCell {
    var sortAscending: Bool?
    var filterActive = false
    var typeName: String?
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        ParquetTableStyle.header.setFill()
        cellFrame.fill()
        let filter = NSRect(x: cellFrame.minX, y: cellFrame.minY + ParquetTableHeaderView.titleHeight,
                            width: cellFrame.width, height: ParquetTableHeaderView.filterHeight)
        (filterActive ? ParquetTableStyle.selection : ParquetTableStyle.filter).setFill()
        filter.fill()
        ParquetTableStyle.grid.setFill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY, width: 1, height: cellFrame.height).fill()
        NSRect(x: cellFrame.minX, y: filter.minY - 1, width: cellFrame.width, height: 1).fill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 2, width: cellFrame.width, height: 2).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        let title = NSAttributedString(string: stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: ParquetTableStyle.Layout.chromeFontSize, weight: .semibold),
            .foregroundColor: alignment == .center ? ParquetTableStyle.mutedText : AppColors.primaryText,
            .paragraphStyle: paragraph,
        ])
        if let sortAscending {
            NSAttributedString(string: sortAscending ? "↑" : "↓", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: AppColors.primaryText,
            ]).draw(in: NSRect(x: cellFrame.maxX - 22, y: cellFrame.minY + (typeName == nil ? 16 : 9), width: 14, height: 19))
        }
        let titleWidth = max(0, cellFrame.width - (sortAscending == nil ? 22 : 40))
        title.draw(in: NSRect(x: cellFrame.minX + ParquetTableStyle.Layout.cellInset, y: cellFrame.minY + (typeName == nil ? 16 : 9),
                              width: titleWidth, height: 19))
        if let typeName {
            NSAttributedString(string: typeName, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: ParquetTableStyle.mutedText.withAlphaComponent(0.8),
                .paragraphStyle: paragraph,
            ]).draw(in: NSRect(x: cellFrame.minX + ParquetTableStyle.Layout.cellInset, y: cellFrame.minY + 28, width: titleWidth, height: 16))
        }
    }
}
