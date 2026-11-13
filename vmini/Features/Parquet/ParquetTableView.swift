import AppKit

struct ParquetCellSelection: Equatable {
    struct Cell: Equatable {
        var row: Int
        var column: Int
    }

    var anchor: Cell
    var focus: Cell

    var rows: ClosedRange<Int> { min(anchor.row, focus.row)...max(anchor.row, focus.row) }
    var columns: ClosedRange<Int> { min(anchor.column, focus.column)...max(anchor.column, focus.column) }
}

/// Replaces row selection with a rectangular cell selection spanning every row and column the drag covers.
final class ParquetTableView: NSTableView {
    var cellSelection: ParquetCellSelection? {
        didSet { if cellSelection != oldValue { refreshCellSelection() } }
    }

    func refreshCellSelection() {
        enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let start = cell(at: event) else { cellSelection = nil; return }
        let wholeRows = tableColumns[start.column].identifier.rawValue == "rowNumber"
        let span = { (cell: ParquetCellSelection.Cell) in wholeRows ? .init(row: cell.row, column: self.numberOfColumns - 1) : cell }
        var anchor = event.modifierFlags.contains(.shift) ? cellSelection?.anchor ?? start : start
        if wholeRows { anchor.column = 0 }
        cellSelection = .init(anchor: anchor, focus: span(start))
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            autoscroll(with: next)
            if let cell = cell(at: next, clamped: true) { cellSelection?.focus = span(cell) }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cellSelection = nil; return }  // Escape
        let moves: [UInt16: (row: Int, column: Int)] = [123: (0, -1), 124: (0, 1), 125: (1, 0), 126: (-1, 0)]
        guard let move = moves[event.keyCode], numberOfRows > 0, numberOfColumns > 0 else { return super.keyDown(with: event) }
        guard let selection = cellSelection else {
            cellSelection = .init(anchor: .init(row: 0, column: min(1, numberOfColumns - 1)),
                                  focus: .init(row: 0, column: min(1, numberOfColumns - 1)))
            return
        }
        let focus = ParquetCellSelection.Cell(row: min(max(selection.focus.row + move.row, 0), numberOfRows - 1),
                                              column: min(max(selection.focus.column + move.column, 0), numberOfColumns - 1))
        cellSelection = .init(anchor: event.modifierFlags.contains(.shift) ? selection.anchor : focus, focus: focus)
        scrollRowToVisible(focus.row)
        scrollColumnToVisible(focus.column)
    }

    override func selectAll(_ sender: Any?) {
        guard numberOfRows > 0, numberOfColumns > 0 else { return }
        cellSelection = .init(anchor: .init(row: 0, column: 0), focus: .init(row: numberOfRows - 1, column: numberOfColumns - 1))
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        item.action == #selector(selectAll(_:)) ? numberOfRows > 0 && numberOfColumns > 0 : super.validateUserInterfaceItem(item)
    }

    override func deselectAll(_ sender: Any?) {
        super.deselectAll(sender)
        cellSelection = nil
    }

    private func cell(at event: NSEvent, clamped: Bool = false) -> ParquetCellSelection.Cell? {
        var point = convert(event.locationInWindow, from: nil)
        if clamped { point.x = min(max(point.x, 0), bounds.maxX - 1); point.y = max(point.y, 0) }
        var row = row(at: point), column = column(at: point)
        if clamped, row < 0 { row = numberOfRows - 1 }
        if clamped, column < 0 { column = numberOfColumns - 1 }
        return row >= 0 && column >= 0 ? .init(row: row, column: column) : nil
    }
}
