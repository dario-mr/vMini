import AppKit

final class ResizeHandleView: NSView {
    var cursor: NSCursor = .arrow

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }
}
