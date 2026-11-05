import AppKit

struct MarkdownTableColumnLayout {
    struct Pipe {
        let range: NSRange
        let column: Int
        let x: CGFloat
    }

    struct Row {
        let range: NSRange
        let rect: NSRect
        let pipes: [Pipe]
        let canAlign: Bool
    }

    let rows: [Row]
    let columns: [Int: CGFloat]
    let outerEdges: [Int: CGFloat]

    func renders(_ pipe: Pipe) -> Bool {
        guard let x = columns[pipe.column] ?? outerEdges[pipe.column] else { return false }
        return abs(pipe.x - x) <= 0.5
    }

    init?(table: MarkdownTable, layoutManager: NSLayoutManager) {
        guard table.range.upperBound <= (layoutManager.textStorage?.length ?? 0),
              let container = layoutManager.textContainers.first else { return nil }
        var rows: [Row] = []
        for row in table.rows {
            let glyphs = layoutManager.glyphRange(forCharacterRange: row.range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return nil }
            let first = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let last = layoutManager.lineFragmentRect(forGlyphAt: glyphs.upperBound - 1, effectiveRange: nil)
            let firstColumn = row.pipes.first == row.contentRange.location ? 0 : 1
            let pipes = row.pipes.enumerated().map { index, location in
                let range = NSRange(location: location, length: 1)
                let pipeGlyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: pipeGlyphs, in: container)
                return Pipe(range: range, column: firstColumn + index, x: rect.midX)
            }
            rows.append(Row(range: row.range, rect: first.union(last), pipes: pipes,
                            canAlign: first.minY == last.minY && row.cells.count == table.columnCount
                                && zip(pipes, pipes.dropFirst()).allSatisfy { $0.x < $1.x }))
        }
        var columns: [Int: CGFloat] = [:]
        if let first = rows.first, first.canAlign {
            columns = Dictionary(uniqueKeysWithValues: first.pipes.map { ($0.column, $0.x) })
        }
        // shortcut: wrapped or misaligned boundaries retain source pipes; format or widen the table to render them.
        for row in rows.dropFirst() {
            guard row.canAlign else { columns.removeAll(); break }
            columns = columns.filter { column, x in
                row.pipes.contains { $0.column == column && abs($0.x - x) <= 0.5 }
            }
        }
        self.rows = rows
        self.columns = columns
        var outerEdges: [Int: CGFloat] = [:]
        if rows.allSatisfy({ $0.canAlign && $0.pipes.first?.column == 0 }) {
            outerEdges[0] = rows.compactMap { $0.pipes.first?.x }.min()
        }
        if rows.allSatisfy({ $0.canAlign && $0.pipes.last?.column == table.columnCount }) {
            outerEdges[table.columnCount] = rows.compactMap { $0.pipes.last?.x }.max()
        }
        self.outerEdges = outerEdges
    }
}
