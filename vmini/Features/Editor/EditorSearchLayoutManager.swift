import AppKit

final class EditorSearchLayoutManager: NSLayoutManager {
    var currentMatch: (() -> NSRange?)?
    var outlineColor: NSColor = .labelColor

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let range = currentMatch?(), range.length > 0,
              NSMaxRange(range) <= (textStorage?.length ?? 0),
              let container = textContainers.first, let textView = container.textView,
              let color = temporaryAttribute(.backgroundColor, atCharacterIndex: range.location, effectiveRange: nil) as? NSColor else { return }

        let selectedGlyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let visibleGlyphs = NSIntersectionRange(selectedGlyphs, glyphsToShow)
        guard visibleGlyphs.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        enumerateEnclosingRects(forGlyphRange: visibleGlyphs, withinSelectedGlyphRange: selectedGlyphs, in: container) { rect, _ in
            let rect = rect.offsetBy(dx: origin.x, dy: origin.y)
            // Cover AppKit's selection before restoring the match background; glyphs draw afterward.
            textView.backgroundColor.setFill()
            rect.fill()
            color.setFill()
            rect.fill()
            self.outlineColor.withAlphaComponent(0.8).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }
}
