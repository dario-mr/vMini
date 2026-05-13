import AppKit

final class TabContentBackgroundView: NSView {
    var onDoubleClickEmptyArea: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClickEmptyArea?()
            return
        }

        super.mouseDown(with: event)
    }
}
