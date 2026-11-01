import AppKit

private enum SelectionOccurrenceStyle {
    static let fillOpacity: CGFloat = 0.2
    static let colorOpacity: CGFloat = 0.95
    static let lineWidth: CGFloat = 1
    static let cornerRadius: CGFloat = 3
    static let horizontalPadding: CGFloat = 2
    static let verticalPadding: CGFloat = 1
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
                _ = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &lineGlyphRange,
                    withoutAdditionalLayout: false
                )
                let segment = NSIntersectionRange(glyphRange, lineGlyphRange)
                if segment.length > 0 {
                    let glyphRect = layoutManager.boundingRect(forGlyphRange: segment, in: textContainer)
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
                        if joinLineFragments, let previousRect, previousRect.intersects(rect) {
                            let overlap = previousRect.intersection(rect)
                            let top = previousRect.maxY - min(SelectionOccurrenceStyle.cornerRadius, previousRect.height / 2)
                            let bottom = rect.minY + min(SelectionOccurrenceStyle.cornerRadius, rect.height / 2)
                            if bottom > top {
                                // Cover adjoining corners along the shared sides before joining the rows.
                                fragments.addRect(NSRect(x: overlap.minX, y: top, width: overlap.width, height: bottom - top))
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
