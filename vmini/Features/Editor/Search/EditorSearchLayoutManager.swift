import AppKit

final class EditorSearchLayoutManager: NSLayoutManager {
    var currentMatch: (() -> NSRange?)?
    var outlineColor: NSColor = .labelColor
    let markdownTables = MarkdownTableCache()
    let markdownTableLayouts = MarkdownTableLayoutCache()
    var markdownTableSelections: [NSRange] = []
    var markdownTableRevision: UInt64?

    override func invalidateLayout(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) {
        markdownTableLayouts.invalidate()
        super.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: actualCharRange)
    }

    override func textContainerChangedGeometry(_ container: NSTextContainer) {
        markdownTableLayouts.invalidate()
        super.textContainerChangedGeometry(container)
    }

    override func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions,
                                 range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        markdownTableLayouts.invalidate()
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange,
                             changeInLength: delta, invalidatedRange: invalidatedCharRange)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Keep the table tint beneath native selection and attributed text backgrounds.
        MarkdownTableRendering.draw(markdownTables.tables, layoutManager: self,
                                    glyphRange: glyphsToShow, origin: origin, color: outlineColor)
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
        }

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let fragments = CGMutablePath()
        var previousRect: NSRect?
        enumerateEnclosingRects(forGlyphRange: selectedGlyphs, withinSelectedGlyphRange: selectedGlyphs, in: container) { rect, _ in
            let rect = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0.5, dy: 0.5)
            guard rect.width > 0, rect.height > 0 else { return }
            fragments.addRect(rect)
            if let previousRect, rect.minY > previousRect.minY {
                let left = max(previousRect.minX, rect.minX)
                let right = min(previousRect.maxX, rect.maxX)
                let top = previousRect.maxY - 0.5
                let bottom = rect.minY + 0.5
                if right > left, bottom > top {
                    fragments.addRect(NSRect(x: left, y: top, width: right - left, height: bottom - top))
                }
            }
            previousRect = rect
        }
        context.addPath(fragments.normalized(using: .winding))
        context.setStrokeColor(outlineColor.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1)
        context.strokePath()
    }
}
