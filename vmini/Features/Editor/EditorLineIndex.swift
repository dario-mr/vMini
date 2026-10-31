import Foundation

struct EditorLineIndex {
    private(set) var lineStarts = [0]

    func lineNumber(forCharacterAt characterIndex: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= characterIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(low, 1)
    }

    mutating func reset(text: NSString) {
        lineStarts = Self.allLineStarts(in: text)
    }

    mutating func update(text: NSString, editedRange: NSRange, changeInLength: Int) {
        guard !lineStarts.isEmpty else {
            lineStarts = Self.allLineStarts(in: text)
            return
        }

        let oldTextLength = max(text.length - changeInLength, 0)
        let oldRangeLength = max(editedRange.length - changeInLength, 0)
        let oldEditStart = min(max(editedRange.location, 0), oldTextLength)
        let oldEditEnd = min(oldEditStart + oldRangeLength, oldTextLength)

        let lineIndex = index(containing: oldEditStart)
        let preservedPrefix = Array(lineStarts.prefix(lineIndex + 1))
        let scanStart = preservedPrefix.last ?? 0

        let oldNextLineIndex = firstLineIndex(startingAfter: oldEditEnd)
        let oldScanEnd = oldNextLineIndex < lineStarts.count ? lineStarts[oldNextLineIndex] : oldTextLength
        let newScanEnd = min(max(oldScanEnd + changeInLength, scanStart), text.length)
        let scannedRange = NSRange(
            location: scanStart,
            length: max(newScanEnd - scanStart, 0)
        )

        var replacementStarts = Self.lineStarts(in: text, range: scannedRange)
        if replacementStarts.first == preservedPrefix.last {
            replacementStarts.removeFirst()
        }

        let shiftedSuffix: [Int]
        if oldNextLineIndex < lineStarts.count {
            shiftedSuffix = lineStarts[oldNextLineIndex...]
                .map { $0 + changeInLength }
                .filter { $0 <= text.length }
        } else {
            shiftedSuffix = []
        }

        lineStarts = Self.uniquedLineStarts(preservedPrefix + replacementStarts + shiftedSuffix)
        if lineStarts.isEmpty || lineStarts[0] != 0 {
            lineStarts.insert(0, at: 0)
        }
    }

    func index(containing location: Int) -> Int {
        max(lineNumber(forCharacterAt: location) - 1, 0)
    }

    private func firstLineIndex(startingAfter location: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func allLineStarts(in text: NSString) -> [Int] {
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<unichar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var starts = [0]
        var base = 0
        while base < text.length {
            let length = min(bufferSize, text.length - base)
            text.getCharacters(buffer, range: NSRange(location: base, length: length))
            for index in 0..<length where buffer[index] == 10 {
                starts.append(base + index + 1)
            }
            base += length
        }
        return starts
    }

    private static func lineStarts(in text: NSString, range: NSRange) -> [Int] {
        guard range.length > 0 else {
            return []
        }

        var starts: [Int] = []
        var searchLocation = range.location
        let rangeEnd = NSMaxRange(range)
        while searchLocation < rangeEnd {
            let newlineRange = text.range(
                of: "\n",
                options: [],
                range: NSRange(location: searchLocation, length: rangeEnd - searchLocation)
            )
            guard newlineRange.location != NSNotFound else {
                break
            }

            let nextLineStart = newlineRange.location + newlineRange.length
            if nextLineStart <= text.length {
                starts.append(nextLineStart)
            }
            searchLocation = nextLineStart
        }

        return starts
    }

    private static func uniquedLineStarts(_ starts: [Int]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(starts.count)
        for start in starts where result.last != start {
            result.append(start)
        }
        return result
    }
}
