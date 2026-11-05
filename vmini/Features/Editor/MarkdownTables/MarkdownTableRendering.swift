import AppKit

enum MarkdownTableRendering {
    private static let syntaxOpacity: CGFloat = 0.06
    private static let selectedSyntaxOpacity: CGFloat = 0.45
    private static let backgroundOpacity: CGFloat = 0.025
    private static let headerBackgroundOpacity: CGFloat = 0.08
    private static let separatorOpacity: CGFloat = 0.12
    private static let outlineOpacity: CGFloat = 0.22
    private static let headerSeparatorWidth: CGFloat = 0.75
    private static let bodySeparatorWidth: CGFloat = 0.5
    private static let cornerRadius: CGFloat = 3.5
    private static let fallbackDecorationPadding = NSSize(width: 3, height: 2)
    private static let headerFontWeight: NSFont.Weight = .semibold

    struct Separator {
        let start: NSPoint
        let end: NSPoint
        let isHeader: Bool
    }

    @MainActor static func updateDelimiterVisibility(in textView: NSTextView) {
        guard let manager = textView.layoutManager as? EditorSearchLayoutManager,
              let storage = textView.textStorage else { return }
        if manager.markdownTableRevision != manager.markdownTables.revision {
            // Edits and invalid tables must not leave ordinary text hidden.
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
            manager.markdownTableLayouts.invalidate()
            manager.markdownTableRevision = manager.markdownTables.revision
        }
        let text = storage.string as NSString
        manager.markdownTableSelections = textView.selectedRanges.map {
            let range = $0.rangeValue.clamped(toLength: text.length)
            return range.length == 0 ? NSRange(location: text.lineRange(for: range).location, length: 0) : range
        }
        for table in manager.markdownTables.tables {
            let row = table.rows[1]
            let color = isSelected(row.range, selections: manager.markdownTableSelections)
                ? manager.outlineColor.withAlphaComponent(selectedSyntaxOpacity) : NSColor.clear
            setForegroundColor(color, for: row.contentRange, layoutManager: manager)
        }
    }

    private static func isSelected(_ row: NSRange, selections: [NSRange]) -> Bool {
        selections.contains { $0.length == 0 ? NSLocationInRange($0.location, row) : $0.intersects(row) }
    }

    private static func setForegroundColor(_ color: NSColor?, for range: NSRange, layoutManager: NSLayoutManager) {
        let current = layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: range.location, effectiveRange: nil) as? NSColor
        guard current != color else { return }
        if let color {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
        } else {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        }
    }

    private static func updatePipeVisibility(_ row: MarkdownTableColumnLayout.Row, columns: MarkdownTableColumnLayout,
                                             isSelected: Bool, layoutManager: NSLayoutManager, color: NSColor) {
        for pipe in row.pipes {
            let desired: NSColor? = isSelected ? color.withAlphaComponent(selectedSyntaxOpacity) : columns.renders(pipe) ? .clear : nil
            setForegroundColor(desired, for: pipe.range, layoutManager: layoutManager)
        }
    }

    @MainActor static func applyStyles(_ tables: [MarkdownTable], to storage: NSTextStorage, in range: NSRange,
                            font: NSFont, theme: SyntaxTheme) {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: font.familyName ?? font.fontName,
            .traits: [NSFontDescriptor.TraitKey.weight: headerFontWeight]
        ])
        let headerFont = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        let dimmedSyntax = theme.plainText.withAlphaComponent(syntaxOpacity)
        for table in tables where table.range.intersects(range) {
            storage.applyFont(font, range: NSIntersectionRange(table.range, range))
            for cell in table.rows[0].cells {
                storage.applyFont(headerFont, range: NSIntersectionRange(cell, range))
            }
            storage.applyForegroundColor(dimmedSyntax, range: NSIntersectionRange(table.rows[1].contentRange, range))
            for row in table.rows {
                for pipe in row.pipes where NSLocationInRange(pipe, range) {
                    storage.applyForegroundColor(dimmedSyntax, range: NSRange(location: pipe, length: 1))
                }
            }
        }
    }

    static func separators(for table: MarkdownTable, layoutManager: NSLayoutManager) -> [Separator] {
        guard table.range.upperBound <= (layoutManager.textStorage?.length ?? 0) else { return [] }
        let glyphs = layoutManager.glyphRange(forCharacterRange: table.range, actualCharacterRange: nil)
        var left = CGFloat.greatestFiniteMagnitude
        var right: CGFloat = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
            left = min(left, used.minX)
            right = max(right, used.maxX)
        }
        guard right > left else { return [] }
        return table.rows.enumerated().compactMap { index, row in
            guard index != 0 else { return nil }
            let rowGlyphs = layoutManager.glyphRange(forCharacterRange: row.range, actualCharacterRange: nil)
            guard rowGlyphs.length > 0 else { return nil }
            let lastFragment = layoutManager.lineFragmentRect(forGlyphAt: rowGlyphs.upperBound - 1, effectiveRange: nil)
            let firstFragment = layoutManager.lineFragmentRect(forGlyphAt: rowGlyphs.location, effectiveRange: nil)
            let y = index == 1 ? firstFragment.union(lastFragment).midY : lastFragment.maxY - 0.5
            return Separator(start: NSPoint(x: left, y: y), end: NSPoint(x: right, y: y), isHeader: index == 1)
        }
    }

    static func draw(_ tables: [MarkdownTable], layoutManager: NSLayoutManager, glyphRange: NSRange,
                     origin: NSPoint, color: NSColor) {
        let visible = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let pixel = 1 / max(abs(context.convertToDeviceSpace(CGSize(width: 1, height: 0)).width), 1)
        for table in tables where table.range.intersects(visible) {
            let manager = layoutManager as? EditorSearchLayoutManager
            let layout = manager?.markdownTableLayouts.layout(for: table, layoutManager: layoutManager)
                ?? MarkdownTableLayoutCache.Layout(table: table, layoutManager: layoutManager)
            let columns = layout.columns
            let selectedRows = Set(table.rows.lazy.filter {
                $0.range.intersects(visible) && isSelected($0.range, selections: manager?.markdownTableSelections ?? [])
            }.map(\.range))
            if let columns {
                for (index, row) in columns.rows.enumerated() where index != 1 && row.range.intersects(visible) {
                    updatePipeVisibility(row, columns: columns, isSelected: selectedRows.contains(row.range),
                                         layoutManager: layoutManager, color: color)
                }
            }
            let separators = layout.separators
            guard let first = separators.first else { continue }
            let tableGlyphs = layoutManager.glyphRange(forCharacterRange: table.range, actualCharacterRange: nil)
            let header = layoutManager.lineFragmentRect(forGlyphAt: tableGlyphs.location, effectiveRange: nil)
            let last = layoutManager.lineFragmentRect(forGlyphAt: tableGlyphs.upperBound - 1, effectiveRange: nil)
            let padded = NSRect(x: first.start.x, y: header.minY, width: first.end.x - first.start.x,
                               height: last.maxY - header.minY)
                .insetBy(dx: -fallbackDecorationPadding.width, dy: -fallbackDecorationPadding.height)
            let left = columns?.outerEdges[0].map { $0 - pixel / 2 } ?? max(padded.minX, header.minX)
            let right = columns?.outerEdges[table.columnCount].map { $0 + pixel / 2 } ?? min(padded.maxX, header.maxX)
            let top = max(padded.minY, 0)
            let bottom = table.range.upperBound == layoutManager.textStorage?.length ? last.maxY : padded.maxY
            let block = NSRect(x: left, y: top, width: right - left, height: bottom - top)
                .offsetBy(dx: origin.x, dy: origin.y)
            let bounds = context.convertToUserSpace(context.convertToDeviceSpace(block).integral)
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: pixel / 2, dy: pixel / 2), xRadius: cornerRadius, yRadius: cornerRadius)
            color.withAlphaComponent(backgroundOpacity).setFill()
            outline.fill()
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            color.withAlphaComponent(headerBackgroundOpacity).setFill()
            NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: first.end.y + origin.y - bounds.minY).fill()
            if let columns {
                color.withAlphaComponent(separatorOpacity).setStroke()
                let verticals = NSBezierPath()
                verticals.lineWidth = pixel
                for (index, row) in columns.rows.enumerated() where row.range.intersects(visible) && !selectedRows.contains(row.range) {
                    let top = index == 0 ? bounds.minY + pixel : row.rect.minY + origin.y
                    let bottom = index == columns.rows.count - 1 ? bounds.maxY - pixel : row.rect.maxY + origin.y
                    for (column, x) in columns.columns where column > 0 && column < table.columnCount {
                        verticals.move(to: NSPoint(x: x + origin.x, y: top))
                        verticals.line(to: NSPoint(x: x + origin.x, y: bottom))
                    }
                }
                verticals.stroke()
            }
            let delimiterColor = layoutManager.temporaryAttribute(.foregroundColor,
                                                                 atCharacterIndex: table.rows[1].contentRange.location,
                                                                 effectiveRange: nil) as? NSColor
            for (index, separator) in separators.enumerated() where separator.isHeader || index < separators.count - 1 {
                guard table.rows[index + 1].range.intersects(visible) else { continue }
                if separator.isHeader && (delimiterColor?.alphaComponent ?? 0) > 0 { continue }
                color.withAlphaComponent(separatorOpacity).setStroke()
                let path = NSBezierPath()
                path.lineWidth = separator.isHeader ? headerSeparatorWidth : bodySeparatorWidth
                path.move(to: NSPoint(x: bounds.minX + pixel, y: separator.start.y + origin.y))
                path.line(to: NSPoint(x: bounds.maxX - pixel, y: separator.end.y + origin.y))
                path.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            if let columns {
                let clip = NSBezierPath(rect: bounds.insetBy(dx: -pixel, dy: -pixel))
                clip.windingRule = .evenOdd
                for row in columns.rows where selectedRows.contains(row.range) {
                    if let pipe = row.pipes.first, pipe.column == 0, columns.renders(pipe) {
                        clip.appendRect(NSRect(x: bounds.minX, y: row.rect.minY + origin.y, width: pixel, height: row.rect.height))
                    }
                    if let pipe = row.pipes.last, pipe.column == table.columnCount, columns.renders(pipe) {
                        clip.appendRect(NSRect(x: bounds.maxX - pixel, y: row.rect.minY + origin.y, width: pixel, height: row.rect.height))
                    }
                }
                clip.addClip()
            }
            color.withAlphaComponent(outlineOpacity).setStroke()
            outline.lineWidth = pixel
            outline.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
