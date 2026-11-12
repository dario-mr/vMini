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
    }

    override func drawSelection(in dirtyRect: NSRect) {
        ParquetTableStyle.selection.setFill()
        dirtyRect.fill()
    }
}
