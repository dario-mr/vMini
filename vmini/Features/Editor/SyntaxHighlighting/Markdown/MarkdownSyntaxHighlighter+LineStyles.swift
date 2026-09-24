import Foundation

enum MarkdownLineStylePlanner {
    static func lineStylePlan(in source: String, targetRange: NSRange, fences: [MarkdownSyntaxHighlighter.FenceBlock]) -> [MarkdownSyntaxHighlighter.LineStyle] {
        lineStylePlan(in: source, targetRange: targetRange, fences: fences, isCancelled: { false }) ?? []
    }

    static func lineStylePlan(
        in source: String,
        targetRange: NSRange,
        fences: [MarkdownSyntaxHighlighter.FenceBlock],
        isCancelled: @Sendable () -> Bool
    ) -> [MarkdownSyntaxHighlighter.LineStyle]? {
        let text = source as NSString
        let targetRange = targetRange.clamped(toLength: text.length)
        guard text.length > 0, targetRange.length > 0 else { return [] }

        var styles: [MarkdownSyntaxHighlighter.LineStyle] = []
        let lineScanRange = text.lineRange(for: targetRange.clamped(toLength: text.length))
        var location = lineScanRange.location
        let scanEnd = lineScanRange.upperBound
        var fenceIndex = MarkdownFenceCache.firstFenceIndex(intersectingOrAfter: location, fences: fences)

        while location < scanEnd, location < text.length {
            guard !isCancelled() else { return nil }
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = MarkdownFenceCache.visibleLineContentsRange(for: lineRange, text: text) ?? lineRange

            if contentRange.intersects(targetRange) {
                let classification = fenceClassification(
                    lineRange: lineRange,
                    contentRange: contentRange,
                    fences: fences,
                    fenceIndex: &fenceIndex
                ) ?? classify(lineRange: lineRange, contentRange: contentRange, in: text)
                switch classification {
                case .fence, .fenceContent:
                    break
                case let .heading(level, markerRange, textRange):
                    let fullHeadingRange = NSUnionRange(markerRange, textRange)
                    appendStyle(.boldFont, range: fullHeadingRange, targetRange: targetRange, to: &styles)
                    appendStyle(.color(.headingMarker), range: markerRange, targetRange: targetRange, to: &styles)
                    appendStyle(.headingText(level: level), range: textRange, targetRange: targetRange, to: &styles)
                    appendInlineStyles(lineRange: contentRange, text: text, targetRange: targetRange, to: &styles)
                case let .blockquote(markerRange):
                    appendStyle(.color(.blockquoteMarker), range: markerRange, targetRange: targetRange, to: &styles)
                    appendInlineStyles(lineRange: contentRange, text: text, targetRange: targetRange, to: &styles)
                case let .unorderedList(markerRange):
                    appendStyle(.color(.listMarker), range: markerRange, targetRange: targetRange, to: &styles)
                    appendInlineStyles(lineRange: contentRange, text: text, targetRange: targetRange, to: &styles)
                case let .orderedList(markerRange):
                    appendStyle(.color(.listMarker), range: markerRange, targetRange: targetRange, to: &styles)
                    appendInlineStyles(lineRange: contentRange, text: text, targetRange: targetRange, to: &styles)
                case let .thematicBreak(breakRange):
                    appendStyle(.color(.thematicBreak), range: breakRange, targetRange: targetRange, to: &styles)
                case .plainText:
                    appendInlineStyles(lineRange: contentRange, text: text, targetRange: targetRange, to: &styles)
                }
            }

            location = lineRange.upperBound
        }
        return styles
    }

    private static func appendInlineStyles(
        lineRange: NSRange,
        text: NSString,
        targetRange: NSRange,
        to styles: inout [MarkdownSyntaxHighlighter.LineStyle]
    ) {
        let line = text.substring(with: lineRange)
        let markersToSkip = inlineCodeRanges(in: line, offset: lineRange.location)

        for range in markersToSkip where range.intersects(targetRange) {
            appendStyle(.color(.inlineCode), range: range, targetRange: targetRange, to: &styles)
        }

        for token in linkTokens(in: line, offset: lineRange.location) {
            appendStyle(.color(.linkText), range: token.textRange, targetRange: targetRange, to: &styles)
            appendStyle(.color(.linkURL), range: token.urlRange, targetRange: targetRange, to: &styles)
        }

        for markerRange in emphasisMarkerRanges(in: line, offset: lineRange.location) where !overlapsAny(markerRange, with: markersToSkip) {
            appendStyle(.color(.emphasisMarker), range: markerRange, targetRange: targetRange, to: &styles)
        }
    }

    private static func appendStyle(
        _ kind: MarkdownSyntaxHighlighter.LineStyle.Kind,
        range: NSRange,
        targetRange: NSRange,
        to styles: inout [MarkdownSyntaxHighlighter.LineStyle]
    ) {
        let visibleRange = NSIntersectionRange(range, targetRange)
        if visibleRange.length > 0 {
            styles.append(MarkdownSyntaxHighlighter.LineStyle(kind: kind, range: visibleRange))
        }
    }

    private enum LineClassification: Sendable {
        case plainText
        case heading(level: Int, markerRange: NSRange, textRange: NSRange)
        case blockquote(markerRange: NSRange)
        case unorderedList(markerRange: NSRange)
        case orderedList(markerRange: NSRange)
        case thematicBreak(range: NSRange)
        case fence
        case fenceContent
    }

    private static func classify(lineRange: NSRange, contentRange: NSRange, in text: NSString) -> LineClassification {
        let line = text.substring(with: contentRange)
        let indent = min(MarkdownFenceCache.leadingWhitespaceCount(in: line), 3)
        let trimmed = String(line.dropFirst(indent))
        let trimmedNSString = trimmed as NSString
        let baseLocation = contentRange.location + indent

        if let headingRange = headingMarkerRange(in: trimmed, baseLocation: baseLocation) {
            let markerLength = headingRange.length
            let textStart = baseLocation + markerLength
            let remainingLength = max(contentRange.upperBound - textStart, 0)
            return .heading(
                level: markerLength,
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

    private static func fenceClassification(
        lineRange: NSRange,
        contentRange: NSRange,
        fences: [MarkdownSyntaxHighlighter.FenceBlock],
        fenceIndex: inout Int
    ) -> LineClassification? {
        while fenceIndex < fences.count, fences[fenceIndex].totalRange.upperBound <= lineRange.location {
            fenceIndex += 1
        }

        guard fenceIndex < fences.count else {
            return nil
        }

        let fence = fences[fenceIndex]
        if fence.openingLineRange == lineRange || fence.closingLineRange == lineRange {
            return .fence
        }

        if fence.contentRange.intersects(contentRange) {
            return .fenceContent
        }

        return nil
    }



    private static func headingMarkerRange(in line: String, baseLocation: Int) -> NSRange? {
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

    private static func unorderedListMarkerRange(in line: NSString, baseLocation: Int) -> NSRange? {
        guard line.length >= 2 else { return nil }
        let marker = line.substring(with: NSRange(location: 0, length: 1))
        guard ["-", "*", "+"].contains(marker),
              line.substring(with: NSRange(location: 1, length: 1)) == " " else {
            return nil
        }

        return NSRange(location: baseLocation, length: 1)
    }

    private static func orderedListMarkerRange(in line: NSString, baseLocation: Int) -> NSRange? {
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

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else {
            return false
        }

        return compact.allSatisfy { $0 == first }
    }

    private static func inlineCodeRanges(in line: String, offset: Int) -> [NSRange] {
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

    private struct LinkToken: Sendable {
        let textRange: NSRange
        let urlRange: NSRange
    }

    private static func linkTokens(in line: String, offset: Int) -> [LinkToken] {
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

    private static func emphasisMarkerRanges(in line: String, offset: Int) -> [NSRange] {
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

    private static func closingMarkerIndex(
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

    private static func overlapsAny(_ range: NSRange, with ranges: [NSRange]) -> Bool {
        ranges.contains(where: { $0.intersects(range) })
    }
}
