import Foundation

enum EditedLineDiff {
    private static let newline: unichar = 10

    /// Indexes of the lines in `currentText` that differ from `savedText`.
    static func lineIndexes(currentText: String, savedText: String) -> Set<Int> {
        let current = currentText as NSString
        let saved = savedText as NSString

        // Perf: diff only the lines between the unchanged head and tail, so the cost follows the edit, not the file.
        let head = commonHead(current, saved)
        if head.length == current.length, head.length == saved.length { return [] }
        let tail = commonTail(current, saved, limit: min(current.length, saved.length) - head.length)

        let currentEnd = current.length - tail.length
        let savedEnd = saved.length - tail.length
        let currentLines = current
            .substring(with: NSRange(location: head.lineStart, length: currentEnd - head.lineStart))
            .components(separatedBy: "\n")
        let savedLines = saved
            .substring(with: NSRange(location: head.lineStart, length: savedEnd - head.lineStart))
            .components(separatedBy: "\n")
        let currentLineCount = head.lineCount + currentLines.count + tail.lineCount

        return Set(currentLines.difference(from: savedLines).compactMap { change in
            let lineIndex: Int
            switch change {
            case let .insert(offset, _, _):
                lineIndex = head.lineCount + offset
            case let .remove(offset, _, _):
                lineIndex = min(head.lineCount + offset, currentLineCount - 1)
            }
            return (0..<currentLineCount).contains(lineIndex) ? lineIndex : nil
        })
    }

    /// The shared prefix, plus the start and index of the line holding the first difference.
    private static func commonHead(_ lhs: NSString, _ rhs: NSString) -> (length: Int, lineStart: Int, lineCount: Int) {
        let limit = min(lhs.length, rhs.length)
        var length = 0
        var lineStart = 0
        var lineCount = 0
        withChunkBuffers { lhsBuffer, rhsBuffer, capacity in
            while length < limit {
                let count = min(capacity, limit - length)
                let range = NSRange(location: length, length: count)
                lhs.getCharacters(lhsBuffer, range: range)
                rhs.getCharacters(rhsBuffer, range: range)
                var matched = 0
                while matched < count, lhsBuffer[matched] == rhsBuffer[matched] {
                    if lhsBuffer[matched] == newline {
                        lineCount += 1
                        lineStart = length + matched + 1
                    }
                    matched += 1
                }
                length += matched
                if matched < count { return }
            }
        }
        return (length, lineStart, lineCount)
    }

    /// The shared whole lines at the end: their length from the first shared newline on, and their count.
    private static func commonTail(_ lhs: NSString, _ rhs: NSString, limit: Int) -> (length: Int, lineCount: Int) {
        var scanned = 0
        var length = 0
        var lineCount = 0
        withChunkBuffers { lhsBuffer, rhsBuffer, capacity in
            while scanned < limit {
                let count = min(capacity, limit - scanned)
                lhs.getCharacters(lhsBuffer, range: NSRange(location: lhs.length - scanned - count, length: count))
                rhs.getCharacters(rhsBuffer, range: NSRange(location: rhs.length - scanned - count, length: count))
                var matched = 0
                while matched < count, lhsBuffer[count - 1 - matched] == rhsBuffer[count - 1 - matched] {
                    matched += 1
                    if lhsBuffer[count - matched] == newline {
                        lineCount += 1
                        length = scanned + matched
                    }
                }
                scanned += matched
                if matched < count { return }
            }
        }
        return (length, lineCount)
    }

    private static func withChunkBuffers(
        _ body: (UnsafeMutablePointer<unichar>, UnsafeMutablePointer<unichar>, Int) -> Void
    ) {
        let capacity = 16 * 1024
        let buffer = UnsafeMutablePointer<unichar>.allocate(capacity: capacity * 2)
        defer { buffer.deallocate() }
        body(buffer, buffer + capacity, capacity)
    }
}
