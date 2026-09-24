import Foundation

enum MarkdownFenceCache {
    private struct OpenFence {
        let lineRange: NSRange
        let marker: Character
        let markerCount: Int
        let infoString: String?
    }

    static func makeFenceCache(in text: NSString) -> MarkdownSyntaxHighlighter.FenceCache {
        makeFenceCache(in: text, isCancelled: { false })!
    }

    static func makeFenceCache(in text: NSString, isCancelled: @Sendable () -> Bool) -> MarkdownSyntaxHighlighter.FenceCache? {
        guard let blocks = fenceBlocks(in: text, isCancelled: isCancelled) else { return nil }
        return MarkdownSyntaxHighlighter.FenceCache(textLength: text.length, blocks: blocks)
    }

    static func updateFenceCache(
        _ cache: MarkdownSyntaxHighlighter.FenceCache,
        editContext: SyntaxHighlightEditContext,
        in text: NSString
    ) -> MarkdownSyntaxHighlighter.FenceCacheUpdate? {
        let replacedRange = editContext.replacementRange
        let replacedLength = (editContext.replacedText as NSString).length
        let replacementLength = (editContext.replacementString as NSString).length
        guard replacedRange.length == replacedLength,
              replacedRange.location <= cache.textLength,
              replacedRange.upperBound <= cache.textLength,
              text.length == cache.textLength - replacedLength + replacementLength else {
            return nil
        }

        if canUpdateFenceOffsetsOnly(
            editContext: editContext,
            replacementLength: replacementLength,
            in: text
        ), let blocks = offsetUpdatedFenceBlocks(
            cache.blocks,
            replacedRange: replacedRange,
            replacementLength: replacementLength
        ) {
            let changedRange = NSRange(location: replacedRange.location, length: replacementLength)
            return MarkdownSyntaxHighlighter.FenceCacheUpdate(
                cache: MarkdownSyntaxHighlighter.FenceCache(textLength: text.length, blocks: blocks),
                highlightRange: surroundingLineRange(around: changedRange, in: text),
                rescannedLineCount: 0
            )
        }

        return rescanFenceCache(cache, editContext: editContext, in: text)
    }

    static func isFenceSensitiveEdit(
        editedRange: NSRange,
        editContext: SyntaxHighlightEditContext,
        in text: NSString
    ) -> Bool {
        if containsFenceMarkerCharacter(editContext.replacedText)
            || containsFenceMarkerCharacter(editContext.replacementString) {
            return true
        }

        let scanRange = surroundingLineRange(around: editedRange, in: text)
        if editContext.replacedText.contains("\n"),
           containsFenceMarkerCharacter(text.substring(with: scanRange)) {
            return true
        }

        var location = scanRange.location
        while location < scanRange.upperBound, location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = visibleLineContentsRange(for: lineRange, text: text) ?? lineRange
            let line = text.substring(with: contentRange)
            let indent = min(leadingWhitespaceCount(in: line), 3)
            let trimmed = String(line.dropFirst(indent))
            if parseFence(in: trimmed) != nil {
                return true
            }
            location = lineRange.upperBound
        }

        return false
    }

    static func surroundingLineRange(around range: NSRange, in text: NSString) -> NSRange {
        let baseLineRange = text.lineRange(for: range.clamped(toLength: text.length))
        var start = baseLineRange.location
        var end = baseLineRange.upperBound

        if start > 0 {
            start = text.lineRange(for: NSRange(location: start - 1, length: 0)).location
        }

        if end < text.length {
            end = text.lineRange(for: NSRange(location: end, length: 0)).upperBound
        }

        return NSRange(location: start, length: max(end - start, 0))
    }

    private static func containsFenceMarkerCharacter(_ text: String) -> Bool {
        text.contains("`") || text.contains("~")
    }

    private static func fenceBlocks(
        in text: NSString,
        isCancelled: @Sendable () -> Bool
    ) -> [MarkdownSyntaxHighlighter.FenceBlock]? {
        var blocks: [MarkdownSyntaxHighlighter.FenceBlock] = []
        var location = 0
        var openFence: OpenFence?

        while location < text.length {
            guard !isCancelled() else { return nil }
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            appendFenceLine(lineRange, in: text, openFence: &openFence, blocks: &blocks)
            location = lineRange.upperBound
        }

        if let openFence {
            let contentStart = openFence.lineRange.upperBound
            blocks.append(MarkdownSyntaxHighlighter.FenceBlock(
                openingLineRange: openFence.lineRange,
                contentRange: NSRange(location: contentStart, length: max(text.length - contentStart, 0)),
                closingLineRange: nil,
                infoString: openFence.infoString
            ))
        }

        return blocks
    }

    private static func appendFenceLine(
        _ lineRange: NSRange,
        in text: NSString,
        openFence: inout OpenFence?,
        blocks: inout [MarkdownSyntaxHighlighter.FenceBlock]
    ) {
        let contentRange = visibleLineContentsRange(for: lineRange, text: text) ?? lineRange
        let line = text.substring(with: contentRange)
        let indent = min(leadingWhitespaceCount(in: line), 3)
        let trimmed = String(line.dropFirst(indent))
        guard let fence = parseFence(in: trimmed) else { return }

        if let currentFence = openFence {
            if currentFence.marker == fence.marker, fence.markerCount >= currentFence.markerCount {
                let contentStart = currentFence.lineRange.upperBound
                blocks.append(MarkdownSyntaxHighlighter.FenceBlock(
                    openingLineRange: currentFence.lineRange,
                    contentRange: NSRange(location: contentStart, length: max(lineRange.location - contentStart, 0)),
                    closingLineRange: lineRange,
                    infoString: currentFence.infoString
                ))
                openFence = nil
            }
        } else {
            openFence = OpenFence(
                lineRange: lineRange,
                marker: fence.marker,
                markerCount: fence.markerCount,
                infoString: fence.infoString
            )
        }
    }

    private static func canUpdateFenceOffsetsOnly(
        editContext: SyntaxHighlightEditContext,
        replacementLength: Int,
        in text: NSString
    ) -> Bool {
        guard !containsFenceMarkerCharacter(editContext.replacedText),
              !containsFenceMarkerCharacter(editContext.replacementString),
              !editContext.replacedText.contains(where: \.isNewline),
              !editContext.replacementString.contains(where: \.isNewline) else {
            return false
        }

        let changedRange = NSRange(location: editContext.replacementRange.location, length: replacementLength)
            .clamped(toLength: text.length)
        let nearbyRange = surroundingLineRange(around: changedRange, in: text)
        return !containsFenceMarkerCharacter(text.substring(with: nearbyRange))
    }

    private static func offsetUpdatedFenceBlocks(
        _ fences: [MarkdownSyntaxHighlighter.FenceBlock],
        replacedRange: NSRange,
        replacementLength: Int
    ) -> [MarkdownSyntaxHighlighter.FenceBlock]? {
        let delta = replacementLength - replacedRange.length
        var updatedBlocks: [MarkdownSyntaxHighlighter.FenceBlock] = []
        updatedBlocks.reserveCapacity(fences.count)
        for fence in fences {
            if replacedRange.upperBound <= fence.openingLineRange.location {
                updatedBlocks.append(offset(fence, by: delta))
                continue
            }

            if let closingLineRange = fence.closingLineRange,
               replacedRange.location >= closingLineRange.upperBound {
                updatedBlocks.append(fence)
                continue
            }

            guard replacedRange.location >= fence.contentRange.location,
                  replacedRange.upperBound <= fence.contentRange.upperBound else {
                return nil
            }

            updatedBlocks.append(MarkdownSyntaxHighlighter.FenceBlock(
                openingLineRange: fence.openingLineRange,
                contentRange: NSRange(
                    location: fence.contentRange.location,
                    length: max(fence.contentRange.length + delta, 0)
                ),
                closingLineRange: fence.closingLineRange.map { offset($0, by: delta) },
                infoString: fence.infoString
            ))
        }
        return updatedBlocks
    }

    private static func rescanFenceCache(
        _ cache: MarkdownSyntaxHighlighter.FenceCache,
        editContext: SyntaxHighlightEditContext,
        in text: NSString
    ) -> MarkdownSyntaxHighlighter.FenceCacheUpdate {
        let replacedRange = editContext.replacementRange
        let replacementLength = (editContext.replacementString as NSString).length
        let delta = replacementLength - replacedRange.length
        let replacementEnd = replacedRange.location + replacementLength

        var scanStart = text.lineRange(for: NSRange(location: replacedRange.location, length: 0)).location
        if scanStart > 0 {
            scanStart = text.lineRange(for: NSRange(location: scanStart - 1, length: 0)).location
        }
        if let affectedFence = fenceBlock(containing: replacedRange.location, in: cache) {
            scanStart = min(scanStart, affectedFence.openingLineRange.location)
        }
        if let openFence = openFence(at: scanStart, in: cache) {
            scanStart = openFence.openingLineRange.location
        }

        var rescannedBlocks: [MarkdownSyntaxHighlighter.FenceBlock] = []
        var openFence: OpenFence?
        var location = scanStart
        var rescannedLineCount = 0
        var convergedOldLocation: Int?
        var convergedNewLocation: Int?

        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            appendFenceLine(lineRange, in: text, openFence: &openFence, blocks: &rescannedBlocks)
            rescannedLineCount += 1
            location = lineRange.upperBound

            guard location >= replacementEnd else { continue }
            let oldLocation = location - delta
            guard oldLocation >= replacedRange.upperBound,
                  oldLocation <= cache.textLength,
                  openFence == nil,
                  !isInsideCachedFence(at: oldLocation, in: cache) else {
                continue
            }

            convergedOldLocation = oldLocation
            convergedNewLocation = location
            break
        }

        if convergedOldLocation == nil, let openFence {
            let contentStart = openFence.lineRange.upperBound
            rescannedBlocks.append(MarkdownSyntaxHighlighter.FenceBlock(
                openingLineRange: openFence.lineRange,
                contentRange: NSRange(location: contentStart, length: max(text.length - contentStart, 0)),
                closingLineRange: nil,
                infoString: openFence.infoString
            ))
        }

        let prefix = cache.blocks.filter { $0.totalRange.upperBound <= scanStart }
        let suffix = cache.blocks
            .filter { $0.openingLineRange.location >= (convergedOldLocation ?? cache.textLength) }
            .map { offset($0, by: delta) }
        let blocks = prefix + rescannedBlocks + suffix
        let scanEnd = convergedNewLocation ?? text.length

        return MarkdownSyntaxHighlighter.FenceCacheUpdate(
            cache: MarkdownSyntaxHighlighter.FenceCache(textLength: text.length, blocks: blocks),
            highlightRange: NSRange(location: scanStart, length: max(scanEnd - scanStart, 0)),
            rescannedLineCount: rescannedLineCount
        )
    }

    private static func fenceBlock(containing location: Int, in cache: MarkdownSyntaxHighlighter.FenceCache) -> MarkdownSyntaxHighlighter.FenceBlock? {
        let index = firstFenceIndex(intersectingOrAfter: location, fences: cache.blocks)
        guard index < cache.blocks.count else {
            return cache.blocks.last.flatMap { fence in
                fence.closingLineRange == nil && fence.totalRange.upperBound == location ? fence : nil
            }
        }

        let fence = cache.blocks[index]
        return fence.openingLineRange.location <= location && location < fence.totalRange.upperBound
            ? fence
            : nil
    }

    private static func openFence(at location: Int, in cache: MarkdownSyntaxHighlighter.FenceCache) -> MarkdownSyntaxHighlighter.FenceBlock? {
        guard let fence = fenceBlock(containing: location, in: cache),
              location >= fence.openingLineRange.upperBound else {
            return nil
        }

        return fence
    }

    private static func isInsideCachedFence(at location: Int, in cache: MarkdownSyntaxHighlighter.FenceCache) -> Bool {
        guard let fence = openFence(at: location, in: cache) else { return false }
        return fence.closingLineRange.map { location < $0.upperBound } ?? true
    }

    private static func offset(_ fence: MarkdownSyntaxHighlighter.FenceBlock, by delta: Int) -> MarkdownSyntaxHighlighter.FenceBlock {
        MarkdownSyntaxHighlighter.FenceBlock(
            openingLineRange: offset(fence.openingLineRange, by: delta),
            contentRange: offset(fence.contentRange, by: delta),
            closingLineRange: fence.closingLineRange.map { offset($0, by: delta) },
            infoString: fence.infoString
        )
    }

    private static func offset(_ range: NSRange, by delta: Int) -> NSRange {
        NSRange(location: range.location + delta, length: range.length)
    }

    private static func parseFence(in line: String) -> (marker: Character, markerCount: Int, infoString: String?)? {
        guard let marker = line.first, marker == "`" || marker == "~" else {
            return nil
        }

        let markerCount = line.prefix { $0 == marker }.count
        guard markerCount >= 3 else {
            return nil
        }

        let suffix = line.dropFirst(markerCount)
        let infoString = suffix.trimmingCharacters(in: .whitespaces)
        return (marker, markerCount, infoString.isEmpty ? nil : infoString)
    }

    static func leadingWhitespaceCount(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    static func visibleLineContentsRange(for lineRange: NSRange, text: NSString) -> NSRange? {
        guard lineRange.length > 0 else {
            return nil
        }

        var length = lineRange.length
        while length > 0 {
            let character = text.character(at: lineRange.location + length - 1)
            if character == 10 || character == 13 {
                length -= 1
            } else {
                break
            }
        }

        return NSRange(location: lineRange.location, length: length)
    }

    static func firstFenceIndex(intersectingOrAfter location: Int, fences: [MarkdownSyntaxHighlighter.FenceBlock]) -> Int {
        var low = 0
        var high = fences.count
        while low < high {
            let mid = (low + high) / 2
            if fences[mid].totalRange.upperBound <= location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
