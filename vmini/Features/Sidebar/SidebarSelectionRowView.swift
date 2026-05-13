import AppKit

final class SidebarSelectionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else {
            return
        }

        AppColors.subtleSelectionFill.setFill()
        let selectionRect = bounds.insetBy(dx: 10, dy: 1)
        NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5).fill()
    }
}
