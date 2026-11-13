import AppKit

@MainActor
enum ParquetTableStyle {
    enum Layout {
        static let cellInset: CGFloat = 11
        static let rowNumberInset: CGFloat = 4
        static let filterControlHeight: CGFloat = 29
        static let filterRowPadding: CGFloat = 6
        static let controlFontSize: CGFloat = 11
        static let chromeFontSize: CGFloat = 14
        static let cellFontSize: CGFloat = 13
    }

    static var header: NSColor { AppColors.windowBackground }
    static var filter: NSColor { blend(AppColors.editorBackground, AppColors.tabBarBackground, 0.4) }
    static var row: NSColor { blend(AppColors.editorBackground, AppColors.tabBarBackground, 0.15) }
    static var alternateRow: NSColor { blend(row, AppColors.primaryText, 0.035) }
    static var grid: NSColor { AppColors.primaryText.withAlphaComponent(0.14) }
    static var searchFill: NSColor { blend(filter, AppColors.primaryText, 0.06) }
    static var searchBorder: NSColor { AppColors.primaryText.withAlphaComponent(0.2) }
    static var focusBorder: NSColor { AppColors.activeControlTint.withAlphaComponent(0.7) }
    static var mutedText: NSColor { blend(AppColors.primaryText, AppColors.editorBackground, 0.4) }
    static var selection: NSColor { blend(row, AppColors.primaryActionBackground, 0.5) }
    static var cellSelection: NSColor { AppColors.primaryActionBackground.withAlphaComponent(0.14) }
    static var cellSelectionBorder: NSColor { AppColors.primaryActionBackground.withAlphaComponent(0.8) }

    private static func blend(_ background: NSColor, _ foreground: NSColor, _ fraction: CGFloat) -> NSColor {
        background.blended(withFraction: fraction, of: foreground) ?? background
    }
}

final class ParquetTableRowView: NSTableRowView {
    var alternate = false { didSet { if alternate != oldValue { needsDisplay = true } } }
    private var hovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if hoverTrackingArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverTrackingArea = area
        }
    }

    func refreshHover() {
        // Scrolling can move a row away from the pointer without delivering mouseExited.
        let isHovered = window.map { $0.isKeyWindow && visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        if hovered != isHovered {
            hovered = isHovered
            needsDisplay = true
        }
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func drawBackground(in dirtyRect: NSRect) {
        let background = alternate ? ParquetTableStyle.alternateRow : ParquetTableStyle.row
        (hovered ? background.blended(withFraction: 0.08, of: AppColors.primaryText) ?? background : background).setFill()
        dirtyRect.fill()
        if let rect = cellSelectionRect() {
            ParquetTableStyle.cellSelection.setFill()
            rect.rect.fill(using: .sourceOver)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let (rect, isTop, isBottom) = cellSelectionRect() else { return }
        let path = NSBezierPath()
        let box = rect.insetBy(dx: 0.5, dy: 0.5)
        path.move(to: NSPoint(x: box.minX, y: rect.minY))
        path.line(to: NSPoint(x: box.minX, y: rect.maxY))
        path.move(to: NSPoint(x: box.maxX, y: rect.minY))
        path.line(to: NSPoint(x: box.maxX, y: rect.maxY))
        if isTop { path.move(to: NSPoint(x: box.minX, y: box.minY)); path.line(to: NSPoint(x: box.maxX, y: box.minY)) }
        if isBottom { path.move(to: NSPoint(x: box.minX, y: box.maxY)); path.line(to: NSPoint(x: box.maxX, y: box.maxY)) }
        ParquetTableStyle.cellSelectionBorder.setStroke()
        path.stroke()
    }

    private func cellSelectionRect() -> (rect: NSRect, isTop: Bool, isBottom: Bool)? {
        guard let table = superview as? ParquetTableView, let selection = table.cellSelection,
              selection.columns.upperBound < table.numberOfColumns else { return nil }
        let row = table.row(for: self)
        guard selection.rows.contains(row) else { return nil }
        let columns = table.rect(ofColumn: selection.columns.lowerBound).union(table.rect(ofColumn: selection.columns.upperBound))
        let rect = NSRect(x: columns.minX - frame.minX, y: 0, width: columns.width, height: bounds.height)
        return (rect, row == selection.rows.lowerBound, row == selection.rows.upperBound)
    }
}
