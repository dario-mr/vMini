import AppKit

@MainActor
final class MarkdownSyntaxHighlighter: SyntaxHighlighter {
    struct FenceBlock {
        let openingLineRange: NSRange
        let contentRange: NSRange
        let closingLineRange: NSRange?
        let infoString: String?

        var totalRange: NSRange {
            let end = closingLineRange?.upperBound ?? contentRange.upperBound
            return NSRange(location: openingLineRange.location, length: max(end - openingLineRange.location, 0))
        }
    }

    let language: SyntaxLanguage = .markdown

    func expandedHighlightRange(for editedRange: NSRange, in text: NSString) -> NSRange {
        let lineRange = text.lineRange(for: editedRange.clamped(toLength: text.length))
        if let containingFence = fenceBlocks(in: text).first(where: { $0.totalRange.intersects(lineRange) }) {
            return containingFence.totalRange
        }

        return lineRange
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        let text = textStorage.string as NSString
        let targetRange = (range ?? NSRange(location: 0, length: text.length)).clamped(toLength: text.length)
        guard text.length > 0, targetRange.length > 0 else {
            return
        }

        let fences = fenceBlocks(in: text)
        applyFenceStyling(textStorage: textStorage, text: text, fences: fences, targetRange: targetRange, theme: theme, registry: registry)
        applyLineStyling(textStorage: textStorage, text: text, fences: fences, targetRange: targetRange, theme: theme)
    }

    private func applyFenceStyling(
        textStorage: NSTextStorage,
        text: NSString,
        fences: [FenceBlock],
        targetRange: NSRange,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        for fence in fences {
            if fence.contentRange.length > 0 {
                let backgroundRange = NSIntersectionRange(fence.contentRange, targetRange)
                if backgroundRange.length > 0 {
                    textStorage.applyBackgroundColor(theme.color(for: .codeBlockBackground), range: backgroundRange)
                }
            }

            if let openingRange = visibleLineContentsRange(for: fence.openingLineRange, text: text),
               openingRange.intersects(targetRange) {
                textStorage.applyForegroundColor(theme.color(for: .codeFence), range: openingRange)
            }

            if let closingLineRange = fence.closingLineRange,
               let closingRange = visibleLineContentsRange(for: closingLineRange, text: text),
               closingRange.intersects(targetRange) {
                textStorage.applyForegroundColor(theme.color(for: .codeFence), range: closingRange)
            }

            guard let infoString = fence.infoString,
                  !infoString.isEmpty,
                  let nestedHighlighter = registry.highlighter(forFenceInfoString: infoString),
                  nestedHighlighter.language != language else {
                continue
            }

            let nestedRange = NSIntersectionRange(fence.contentRange, targetRange)
            guard nestedRange.length > 0 else {
                continue
            }

            nestedHighlighter.highlight(
                textStorage: textStorage,
                in: nestedRange,
                theme: theme,
                registry: registry
            )
        }
    }

    private func applyLineStyling(
        textStorage: NSTextStorage,
        text: NSString,
        fences: [FenceBlock],
        targetRange: NSRange,
        theme: SyntaxTheme
    ) {
        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = visibleLineContentsRange(for: lineRange, text: text) ?? lineRange

            if contentRange.intersects(targetRange) {
                let classification = classify(lineRange: lineRange, contentRange: contentRange, in: text, fences: fences)
                switch classification {
                case .fence, .fenceContent:
                    break
                case let .heading(markerRange, textRange):
                    applyIfIntersecting(textStorage: textStorage, theme: theme, role: .headingMarker, range: markerRange, targetRange: targetRange)
                    applyIfIntersecting(textStorage: textStorage, theme: theme, role: .headingText, range: textRange, targetRange: targetRange)
                    applyInlineStyling(textStorage: textStorage, lineRange: contentRange, text: text, theme: theme, targetRange: targetRange)
                case let .blockquote(markerRange):
                    applyIfIntersecting(textStorage: textStorage, theme: theme, role: .blockquoteMarker, range: markerRange, targetRange: targetRange)
                    applyInlineStyling(textStorage: textStorage, lineRange: contentRange, text: text, theme: theme, targetRange: targetRange)
                case let .unorderedList(markerRange):
                    applyIfIntersecting(textStorage: textStorage, theme: theme, role: .listMarker, range: markerRange, targetRange: targetRange)
                    applyInlineStyling(textStorage: textStorage, lineRange: contentRange, text: text, theme: theme, targetRange: targetRange)
                case let .orderedList(markerRange):
                    applyIfIntersecting(textStorage: textStorage, theme: theme, role: .listMarker, range: markerRange, targetRange: targetRange)
                    applyInlineStyling(textStorage: textStorage, lineRange: contentRange, text: text, theme: theme, targetRange: targetRange)
                case let .thematicBreak(breakRange):
                    applyIfIntersecting(textStorage: textStorage, theme: theme, role: .thematicBreak, range: breakRange, targetRange: targetRange)
                case .plainText:
                    applyInlineStyling(textStorage: textStorage, lineRange: contentRange, text: text, theme: theme, targetRange: targetRange)
                }
            }

            location = lineRange.upperBound
        }
    }

    private func applyInlineStyling(
        textStorage: NSTextStorage,
        lineRange: NSRange,
        text: NSString,
        theme: SyntaxTheme,
        targetRange: NSRange
    ) {
        let line = text.substring(with: lineRange)
        let markersToSkip = inlineCodeRanges(in: line, offset: lineRange.location)

        for range in markersToSkip where range.intersects(targetRange) {
            textStorage.applyForegroundColor(theme.color(for: .inlineCode), range: range)
        }

        for token in linkTokens(in: line, offset: lineRange.location) {
            applyIfIntersecting(textStorage: textStorage, theme: theme, role: .linkText, range: token.textRange, targetRange: targetRange)
            applyIfIntersecting(textStorage: textStorage, theme: theme, role: .linkURL, range: token.urlRange, targetRange: targetRange)
        }

        for markerRange in emphasisMarkerRanges(in: line, offset: lineRange.location) where !overlapsAny(markerRange, with: markersToSkip) {
            applyIfIntersecting(textStorage: textStorage, theme: theme, role: .emphasisMarker, range: markerRange, targetRange: targetRange)
        }
    }

    private func applyIfIntersecting(
        textStorage: NSTextStorage,
        theme: SyntaxTheme,
        role: SyntaxColorRole,
        range: NSRange,
        targetRange: NSRange
    ) {
        let visibleRange = NSIntersectionRange(range, targetRange)
        guard visibleRange.length > 0 else { return }
        textStorage.applyForegroundColor(theme.color(for: role), range: visibleRange)
    }

    private enum LineClassification {
        case plainText
        case heading(markerRange: NSRange, textRange: NSRange)
        case blockquote(markerRange: NSRange)
        case unorderedList(markerRange: NSRange)
        case orderedList(markerRange: NSRange)
        case thematicBreak(range: NSRange)
        case fence
        case fenceContent
    }

    private func classify(lineRange: NSRange, contentRange: NSRange, in text: NSString, fences: [FenceBlock]) -> LineClassification {
        if fences.contains(where: { $0.openingLineRange == lineRange || $0.closingLineRange == lineRange }) {
            return .fence
        }

        if fences.contains(where: { $0.contentRange.intersects(contentRange) }) {
            return .fenceContent
        }

        let line = text.substring(with: contentRange)
        let indent = min(leadingWhitespaceCount(in: line), 3)
        let trimmed = String(line.dropFirst(indent))
        let trimmedNSString = trimmed as NSString
        let baseLocation = contentRange.location + indent

        if let headingRange = headingMarkerRange(in: trimmed, baseLocation: baseLocation) {
            let markerLength = headingRange.length
            let textStart = baseLocation + markerLength
            let remainingLength = max(contentRange.upperBound - textStart, 0)
            return .heading(
                markerRange: headingRange,
                textRange: NSRange(location: textStart, length: remainingLength)
            )
        }

        if trimmed.hasPrefix(">") {
            return .blockquote(markerRange: NSRange(location: baseLocation, length: 1))
        }

        if let unorderedMarker = unorderedListMarkerRange(in: trimmedNSString, baseLocation: baseLocation) {
            return .unorderedList(markerRange: unorderedMarker)
        }

        if let orderedMarker = orderedListMarkerRange(in: trimmedNSString, baseLocation: baseLocation) {
            return .orderedList(markerRange: orderedMarker)
        }

        if isThematicBreak(trimmed) {
            return .thematicBreak(range: contentRange)
        }

        return .plainText
    }

    private func headingMarkerRange(in line: String, baseLocation: Int) -> NSRange? {
        var count = 0
        for character in line {
            if character == "#" {
                count += 1
            } else {
                break
            }
        }

        guard count > 0, count <= 6 else {
            return nil
        }

        let nextIndex = line.index(line.startIndex, offsetBy: count)
        guard nextIndex == line.endIndex || line[nextIndex].isWhitespace else {
            return nil
        }

        return NSRange(location: baseLocation, length: count)
    }

    private func unorderedListMarkerRange(in line: NSString, baseLocation: Int) -> NSRange? {
        guard line.length >= 2 else { return nil }
        let marker = line.substring(with: NSRange(location: 0, length: 1))
        guard ["-", "*", "+"].contains(marker),
              line.substring(with: NSRange(location: 1, length: 1)) == " " else {
            return nil
        }

        return NSRange(location: baseLocation, length: 1)
    }

    private func orderedListMarkerRange(in line: NSString, baseLocation: Int) -> NSRange? {
        var digitCount = 0
        while digitCount < line.length {
            let character = line.character(at: digitCount)
            guard CharacterSet.decimalDigits.contains(UnicodeScalar(character)!) else {
                break
            }
            digitCount += 1
        }

        guard digitCount > 0, digitCount < line.length else {
            return nil
        }

        let separator = line.substring(with: NSRange(location: digitCount, length: 1))
        guard [".", ")"].contains(separator) else {
            return nil
        }

        let markerEnd = digitCount + 1
        if markerEnd < line.length {
            let following = line.substring(with: NSRange(location: markerEnd, length: 1))
            guard following == " " || following == "\t" else {
                return nil
            }
        }

        return NSRange(location: baseLocation, length: digitCount + 1)
    }

    private func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else {
            return false
        }

        return compact.allSatisfy { $0 == first }
    }

    private func fenceBlocks(in text: NSString) -> [FenceBlock] {
        var blocks: [FenceBlock] = []
        var location = 0
        var openFence: (lineRange: NSRange, marker: Character, markerCount: Int, infoString: String?)?

        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = visibleLineContentsRange(for: lineRange, text: text) ?? lineRange
            let line = text.substring(with: contentRange)
            let indent = min(leadingWhitespaceCount(in: line), 3)
            let trimmed = String(line.dropFirst(indent))

            if let fence = parseFence(in: trimmed) {
                if let currentFence = openFence,
                   currentFence.marker == fence.marker,
                   fence.markerCount >= currentFence.markerCount {
                    let contentStart = currentFence.lineRange.upperBound
                    let contentLength = max(lineRange.location - contentStart, 0)
                    blocks.append(FenceBlock(
                        openingLineRange: currentFence.lineRange,
                        contentRange: NSRange(location: contentStart, length: contentLength),
                        closingLineRange: lineRange,
                        infoString: currentFence.infoString
                    ))
                    openFence = nil
                } else if openFence == nil {
                    openFence = (lineRange, fence.marker, fence.markerCount, fence.infoString)
                }
            }

            location = lineRange.upperBound
        }

        if let openFence {
            let contentStart = openFence.lineRange.upperBound
            blocks.append(FenceBlock(
                openingLineRange: openFence.lineRange,
                contentRange: NSRange(location: contentStart, length: max(text.length - contentStart, 0)),
                closingLineRange: nil,
                infoString: openFence.infoString
            ))
        }

        return blocks
    }

    private func parseFence(in line: String) -> (marker: Character, markerCount: Int, infoString: String?)? {
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

    private func inlineCodeRanges(in line: String, offset: Int) -> [NSRange] {
        let characters = Array(line)
        var ranges: [NSRange] = []
        var index = 0

        while index < characters.count {
            guard characters[index] == "`" else {
                index += 1
                continue
            }

            let start = index
            index += 1

            while index < characters.count, characters[index] != "`" {
                index += 1
            }

            guard index < characters.count else {
                break
            }

            let length = index - start + 1
            ranges.append(NSRange(location: offset + start, length: length))
            index += 1
        }

        return ranges
    }

    private struct LinkToken {
        let textRange: NSRange
        let urlRange: NSRange
    }

    private func linkTokens(in line: String, offset: Int) -> [LinkToken] {
        let characters = Array(line)
        var tokens: [LinkToken] = []
        var index = 0

        while index < characters.count {
            guard characters[index] == "[" else {
                index += 1
                continue
            }

            guard let textEnd = characters[(index + 1)...].firstIndex(of: "]"),
                  textEnd + 1 < characters.count,
                  characters[textEnd + 1] == "(",
                  let urlEnd = characters[(textEnd + 2)...].firstIndex(of: ")") else {
                index += 1
                continue
            }

            tokens.append(LinkToken(
                textRange: NSRange(location: offset + index, length: textEnd - index + 1),
                urlRange: NSRange(location: offset + textEnd + 1, length: urlEnd - textEnd)
            ))
            index = urlEnd + 1
        }

        return tokens
    }

    private func emphasisMarkerRanges(in line: String, offset: Int) -> [NSRange] {
        let characters = Array(line)
        var ranges: [NSRange] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]
            guard character == "*" || character == "_" else {
                index += 1
                continue
            }

            let markerLength = (index + 1 < characters.count && characters[index + 1] == character) ? 2 : 1
            let contentStart = index + markerLength
            guard contentStart < characters.count else {
                index += markerLength
                continue
            }

            if let closeIndex = closingMarkerIndex(
                in: characters,
                marker: character,
                markerLength: markerLength,
                searchStart: contentStart
            ) {
                ranges.append(NSRange(location: offset + index, length: markerLength))
                ranges.append(NSRange(location: offset + closeIndex, length: markerLength))
                index = closeIndex + markerLength
            } else {
                index += markerLength
            }
        }

        return ranges
    }

    private func closingMarkerIndex(
        in characters: [Character],
        marker: Character,
        markerLength: Int,
        searchStart: Int
    ) -> Int? {
        var index = searchStart
        while index + markerLength - 1 < characters.count {
            if markerLength == 2 {
                if characters[index] == marker && characters[index + 1] == marker {
                    return index
                }
            } else if characters[index] == marker {
                return index
            }

            index += 1
        }

        return nil
    }

    private func leadingWhitespaceCount(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private func visibleLineContentsRange(for lineRange: NSRange, text: NSString) -> NSRange? {
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

    private func overlapsAny(_ range: NSRange, with ranges: [NSRange]) -> Bool {
        ranges.contains(where: { $0.intersects(range) })
    }
}
