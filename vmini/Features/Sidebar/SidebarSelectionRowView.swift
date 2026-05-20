import AppKit

final class SidebarSelectionRowView: NSTableRowView {
    private enum Layout {
        static let cornerRadius: CGFloat = 5
        static let horizontalInset: CGFloat = 10
        static let verticalInset: CGFloat = 1
        static let hoverOverlayOpacity: CGFloat = 0.08
    }

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            needsDisplay = true
        }
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        guard isHovered, !isSelected else {
            return
        }

        NSColor.white.withAlphaComponent(Layout.hoverOverlayOpacity).setFill()
        hoverRectPath.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else {
            return
        }

        AppColors.subtleSelectionFill.setFill()
        hoverRectPath.fill()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }

    private var hoverRectPath: NSBezierPath {
        let rect = bounds.insetBy(dx: Layout.horizontalInset, dy: Layout.verticalInset)
        return NSBezierPath(roundedRect: rect, xRadius: Layout.cornerRadius, yRadius: Layout.cornerRadius)
    }
}
