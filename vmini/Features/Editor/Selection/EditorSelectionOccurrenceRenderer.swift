import AppKit

private enum SelectionOccurrenceStyle {
    static let fillOpacity: CGFloat = 0.2
    static let colorOpacity: CGFloat = 0.95
    static let lineWidth: CGFloat = 1
    static let cornerRadius: CGFloat = 3
    static let horizontalPadding: CGFloat = -1
    static let verticalPadding: CGFloat = -1
}

@MainActor
enum EditorSelectionOccurrenceRenderer {
    static func draw(
        in textView: NSTextView,
        dirtyRect: NSRect,
        ranges: [NSRange],
        color: NSColor?,
        filled: Bool = false,
        joinLineFragments: Bool = false
    ) {
        guard let color,
              let context = NSGraphicsContext.current?.cgContext,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let origin = textView.textContainerOrigin
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: dirtyRect.insetBy(
                dx: -SelectionOccurrenceStyle.horizontalPadding - SelectionOccurrenceStyle.lineWidth,
                dy: -SelectionOccurrenceStyle.verticalPadding - SelectionOccurrenceStyle.lineWidth
            ).offsetBy(dx: -origin.x, dy: -origin.y),
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        let documentLength = (textView.string as NSString).length
        let path = CGMutablePath()

        for range in ranges {
            guard range.location >= 0, range.length > 0,
                  range.location < documentLength,
                  range.length <= documentLength - range.location,
                  NSIntersectionRange(range, visibleCharacterRange).length > 0 else { continue }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphRange, visibleGlyphRange).length > 0 else { continue }

            let fragments = CGMutablePath()
            var previousRect: NSRect?
            var glyphIndex = glyphRange.location
            while glyphIndex < NSMaxRange(glyphRange) {
                var lineGlyphRange = NSRange()
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &lineGlyphRange,
                    withoutAdditionalLayout: false
                )
                let segment = NSIntersectionRange(glyphRange, lineGlyphRange)
                if segment.length > 0 {
                    // The last newline before the document end reports a rect starting at x = 0, so keep it in
                    // the text column; it still spans the empty extra line after it, which the selection covers.
                    let extraLine = layoutManager.extraLineFragmentRect
                    let rowRect = NSMaxRange(range) == documentLength && NSMaxRange(segment) == NSMaxRange(glyphRange)
                        && !extraLine.isEmpty ? lineRect.union(extraLine) : lineRect
                    let glyphRect = layoutManager.boundingRect(forGlyphRange: segment, in: textContainer)
                        .intersection(rowRect.insetBy(dx: textContainer.lineFragmentPadding, dy: 0))
                    if glyphRect.width > 0 {
                        let rect = glyphRect.offsetBy(dx: origin.x, dy: origin.y).insetBy(
                            dx: -SelectionOccurrenceStyle.horizontalPadding,
                            dy: -SelectionOccurrenceStyle.verticalPadding
                        )
                        fragments.addRoundedRect(
                            in: rect,
                            cornerWidth: SelectionOccurrenceStyle.cornerRadius,
                            cornerHeight: SelectionOccurrenceStyle.cornerRadius
                        )
                        if joinLineFragments, let previousRect,
                           max(previousRect.minX, rect.minX) < min(previousRect.maxX, rect.maxX) {
                            let overlapMinX = max(previousRect.minX, rect.minX)
                            let overlapWidth = min(previousRect.maxX, rect.maxX) - overlapMinX
                            let top = previousRect.maxY - min(SelectionOccurrenceStyle.cornerRadius, previousRect.height / 2)
                            let bottom = rect.minY + min(SelectionOccurrenceStyle.cornerRadius, rect.height / 2)
                            if bottom > top {
                                // Cover adjoining corners along the shared sides before joining the rows.
                                fragments.addRect(NSRect(x: overlapMinX, y: top, width: overlapWidth, height: bottom - top))
                            }
                        }
                        previousRect = rect
                    }
                }

                let nextGlyphIndex = NSMaxRange(lineGlyphRange)
                guard nextGlyphIndex > glyphIndex else { break }
                glyphIndex = nextGlyphIndex
            }

            path.addPath(joinLineFragments ? fragments.normalized(using: .winding) : fragments)
        }

        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        if filled {
            context.setFillColor(color.withAlphaComponent(SelectionOccurrenceStyle.fillOpacity).cgColor)
            context.fillPath()
        } else {
            context.setStrokeColor(color.withAlphaComponent(SelectionOccurrenceStyle.colorOpacity).cgColor)
            context.setLineWidth(SelectionOccurrenceStyle.lineWidth)
            context.strokePath()
        }
    }
}
