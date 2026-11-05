import AppKit

enum MarkdownTableFormatter {
    static func mapLocation(_ location: Int, in table: MarkdownTable, to formatted: MarkdownTable) -> Int {
        guard let index = table.rows.firstIndex(where: { NSLocationInRange(location, $0.range) }) else {
            return formatted.range.upperBound
        }
        let row = table.rows[index]
        let target = formatted.rows[index]
        if location == row.range.location { return target.range.location }
        if location >= row.contentRange.upperBound {
            return target.contentRange.upperBound + min(location - row.contentRange.upperBound,
                                                        target.range.upperBound - target.contentRange.upperBound)
        }
        let column = row.cells.firstIndex(where: { location <= $0.upperBound }) ?? row.cells.count - 1
        let cell = target.cells[column]
        return cell.location + min(max(location - row.cells[column].location, 0), cell.length)
    }

    static func format(_ table: MarkdownTable, in text: NSString, font: NSFont) -> String {
        let rows = table.rows.map { $0.cells.map { text.substring(with: $0) } }
        let count = max(table.columnCount, rows.map(\.count).max() ?? 0)
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        func width(_ value: String) -> Int {
            // Measure source with the editor font, including fallback glyphs, instead of counting UTF-16 units.
            Int(ceil((value as NSString).size(withAttributes: [.font: font]).width / max(spaceWidth, 1)))
        }
        var widths = Array(repeating: 3, count: count)
        for (index, cells) in rows.enumerated() where index != 1 {
            for (column, value) in cells.enumerated() { widths[column] = max(widths[column], width(value)) }
        }
        return table.rows.enumerated().map { index, row in
            let cells = (0..<max(table.columnCount, rows[index].count)).map { column -> String in
                let value = column < rows[index].count ? rows[index][column] : ""
                let alignment = column < table.columnCount ? table.alignments[column] : .left
                if index == 1 {
                    // Preserve an explicit left-alignment colon as well as center/right markers.
                    let left = value.hasPrefix(":") ? ":" : ""
                    let right = value.hasSuffix(":") ? ":" : ""
                    return left + String(repeating: "-", count: widths[column] - left.count - right.count) + right
                }
                let padding = max(0, widths[column] - width(value))
                let leading = alignment == .right ? padding : alignment == .center ? padding / 2 : 0
                return String(repeating: " ", count: leading) + value + String(repeating: " ", count: padding - leading)
            }
            let indentRange = NSRange(location: row.range.location, length: row.contentRange.location - row.range.location)
            let visible = MarkdownFenceCache.visibleLineContentsRange(for: row.range, text: text)!
            let endingRange = NSRange(location: visible.upperBound, length: row.range.upperBound - visible.upperBound)
            let ending = text.substring(with: endingRange)
            return text.substring(with: indentRange) + "| " + cells.joined(separator: " | ") + " |" + ending
        }.joined()
    }
}
