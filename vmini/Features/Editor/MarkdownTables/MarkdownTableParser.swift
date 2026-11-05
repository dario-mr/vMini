import Foundation

struct MarkdownTable: Equatable {
    enum Alignment: Equatable { case left, center, right }

    struct Row: Equatable {
        let range: NSRange
        let contentRange: NSRange
        let cells: [NSRange]
        let pipes: [Int]
    }

    let range: NSRange
    let rows: [Row]
    let alignments: [Alignment]
    var columnCount: Int { alignments.count }

    func shifted(by delta: Int) -> MarkdownTable {
        func shift(_ range: NSRange) -> NSRange {
            NSRange(location: range.location + delta, length: range.length)
        }
        return MarkdownTable(range: shift(range), rows: rows.map {
            Row(range: shift($0.range), contentRange: shift($0.contentRange),
                cells: $0.cells.map(shift), pipes: $0.pipes.map { $0 + delta })
        }, alignments: alignments)
    }
}

enum MarkdownTableParser {
    static func parse(_ text: NSString, in requestedRange: NSRange? = nil,
                      excluding excludedRanges: [NSRange]? = nil) -> [MarkdownTable] {
        let range = (requestedRange ?? NSRange(location: 0, length: text.length)).clamped(toLength: text.length)
        guard text.range(of: "|", options: .literal, range: range).location != NSNotFound else { return [] }
        let excludedRanges = (excludedRanges ?? (MarkdownFenceCache.makeFenceCache(in: text).blocks.map(\.totalRange)
            + MarkdownHTMLBlocks.ranges(in: text))).sorted { $0.location < $1.location }
        var tables: [MarkdownTable] = []
        var location = range.location
        var excludedIndex = 0
        func nextRow(at location: Int, delimiter: Bool = false) -> MarkdownTable.Row? {
            guard location < range.upperBound else { return nil }
            while excludedIndex < excludedRanges.count, excludedRanges[excludedIndex].upperBound <= location {
                excludedIndex += 1
            }
            guard excludedIndex == excludedRanges.count || !NSLocationInRange(location, excludedRanges[excludedIndex]) else { return nil }
            return row(in: text, at: location, delimiter: delimiter)
        }
        while location < range.upperBound {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            guard text.range(of: "|", options: .literal, range: line).location != NSNotFound,
                  let header = nextRow(at: location), !header.pipes.isEmpty,
                  let separator = nextRow(at: line.upperBound, delimiter: true),
                  separator.cells.count == header.cells.count,
                  let alignments = alignments(for: separator, in: text) else {
                location = line.upperBound
                continue
            }
            var rows = [header, separator]
            location = separator.range.upperBound
            while let body = nextRow(at: location) {
                rows.append(body)
                location = body.range.upperBound
            }
            tables.append(MarkdownTable(
                range: NSRange(location: header.range.location, length: rows.last!.range.upperBound - header.range.location),
                rows: rows, alignments: alignments
            ))
        }
        return tables
    }

    static func blockRange(around range: NSRange, in text: NSString) -> NSRange {
        var block = text.lineRange(for: range.clamped(toLength: text.length))
        func isBlank(_ line: NSRange) -> Bool {
            text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        while block.location > 0 {
            let previous = text.lineRange(for: NSRange(location: block.location - 1, length: 0))
            block = NSUnionRange(block, previous)
            if isBlank(previous) { break }
        }
        while block.upperBound < text.length {
            let next = text.lineRange(for: NSRange(location: block.upperBound, length: 0))
            block = NSUnionRange(block, next)
            if isBlank(next) { break }
        }
        return block.clamped(toLength: text.length)
    }

    private static func row(in text: NSString, at location: Int, delimiter: Bool) -> MarkdownTable.Row? {
        let line = text.lineRange(for: NSRange(location: location, length: 0))
        let visible = MarkdownFenceCache.visibleLineContentsRange(for: line, text: text)!
        let content = trimmed(visible, in: text)
        guard content.length > 0, content.location - line.location <= 3 else { return nil }
        let indentation = NSRange(location: line.location, length: content.location - line.location)
        guard !text.substring(with: indentation).contains("\t") else { return nil }
        let source = text.substring(with: content)
        // nested tables stay plain source; add container parsing when list/quote tables are needed.
        guard delimiter || source.range(of: #"^(?:#{1,6}(?:\s|$)|>|[-+*]\s|\d+[.)]\s|`{3,}|~{3,}|(?:\*\s*){3,}$|(?:_\s*){3,}$|(?:-\s*){3,}$)"#,
                           options: .regularExpression) == nil else { return nil }
        var pipes: [Int] = []
        var index = content.location
        while index < content.upperBound {
            let character = text.character(at: index)
            if character == 92 { // Escapes also handle even/odd backslashes before a pipe.
                index += min(2, content.upperBound - index)
            } else {
                if character == 124 { pipes.append(index) }
                index += 1
            }
        }
        let start = pipes.first == content.location ? content.location + 1 : content.location
        let end = pipes.last == content.upperBound - 1 ? content.upperBound - 1 : content.upperBound
        guard end >= start else { return nil }
        let innerPipes = pipes.filter { $0 >= start && $0 < end }
        var cells: [NSRange] = []
        var cellStart = start
        for pipe in innerPipes {
            cells.append(trimmed(NSRange(location: cellStart, length: pipe - cellStart), in: text))
            cellStart = pipe + 1
        }
        cells.append(trimmed(NSRange(location: cellStart, length: end - cellStart), in: text))
        return MarkdownTable.Row(range: line, contentRange: content, cells: cells, pipes: pipes)
    }

    private static func alignments(for row: MarkdownTable.Row, in text: NSString) -> [MarkdownTable.Alignment]? {
        var result: [MarkdownTable.Alignment] = []
        for cell in row.cells {
            let marker = text.substring(with: cell)
            guard marker.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil else { return nil }
            result.append(marker.hasSuffix(":") ? (marker.hasPrefix(":") ? .center : .right) : .left)
        }
        return result
    }

    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = range.upperBound
        while start < end, text.character(at: start) == 32 || text.character(at: start) == 9 { start += 1 }
        while end > start, text.character(at: end - 1) == 32 || text.character(at: end - 1) == 9 { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
