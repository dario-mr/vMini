import AppKit

private enum SelectionOccurrenceStyle {
    static let colorOpacity: CGFloat = 0.95
    static let lineWidth: CGFloat = 1
    static let cornerRadius: CGFloat = 3
    static let horizontalPadding: CGFloat = 2
    static let verticalPadding: CGFloat = 1
}

@MainActor
enum EditorSelectionOccurrenceRenderer {
    static func draw(in textView: NSTextView, dirtyRect: NSRect, ranges: [NSRange], color: NSColor?) {
        guard let color,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let origin = textView.textContainerOrigin
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y),
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        let documentLength = (textView.string as NSString).length
        let path = NSBezierPath()
        path.lineWidth = SelectionOccurrenceStyle.lineWidth

        for range in ranges {
            guard range.location >= 0, range.length > 0,
                  range.location < documentLength,
                  range.length <= documentLength - range.location,
                  NSIntersectionRange(range, visibleCharacterRange).length > 0 else { continue }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphRange, visibleGlyphRange).length > 0 else { continue }

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
                        path.append(NSBezierPath(
                            roundedRect: rect,
                            xRadius: SelectionOccurrenceStyle.cornerRadius,
                            yRadius: SelectionOccurrenceStyle.cornerRadius
                        ))
                    }
                }

                let nextGlyphIndex = NSMaxRange(lineGlyphRange)
                guard nextGlyphIndex > glyphIndex else { break }
                glyphIndex = nextGlyphIndex
            }
        }

        color.withAlphaComponent(SelectionOccurrenceStyle.colorOpacity).setStroke()
        path.stroke()
    }
}
