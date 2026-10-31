import Foundation

enum EditorWordSelection {
    static func wordSelectionRange(
        in text: NSString,
        proposedRange range: NSRange,
        at index: Int,
        anchoredAt anchor: NSRange? = nil
    ) -> NSRange {
        let segment = dottedSegment(in: range, at: index, text: text) ?? range
        return anchor.map { NSUnionRange($0, segment) } ?? segment
    }

    private static func dottedSegment(in range: NSRange, at index: Int, text: NSString) -> NSRange? {
        let end = NSMaxRange(range)
        let dot: unichar = 46
        var start = index

        if text.character(at: index) == dot {
            start += 1
            while start < end && text.character(at: start) == dot { start += 1 }
            if start == end {
                start = index
                while start > range.location && text.character(at: start - 1) == dot { start -= 1 }
                guard start > range.location else { return nil }
                var previousStart = start - 1
                while previousStart > range.location && text.character(at: previousStart - 1) != dot { previousStart -= 1 }
                return NSRange(location: previousStart, length: start - previousStart)
            }
        } else {
            while start > range.location && text.character(at: start - 1) != dot { start -= 1 }
        }

        var segmentEnd = start
        while segmentEnd < end && text.character(at: segmentEnd) != dot { segmentEnd += 1 }
        return segmentEnd > start ? NSRange(location: start, length: segmentEnd - start) : nil
    }
}
