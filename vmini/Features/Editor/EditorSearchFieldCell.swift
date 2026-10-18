import AppKit

@MainActor
final class EditorSearchFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds bounds: NSRect) -> NSRect {
        var rect = super.drawingRect(forBounds: bounds)
        guard let font else { return rect }
        let height = min(rect.height, ceil(NSLayoutManager().defaultLineHeight(for: font)))
        rect.origin.y += (rect.height - height) / 2
        rect.size.height = height
        return rect
    }
}
