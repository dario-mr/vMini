import AppKit

@MainActor
final class DotenvSyntaxHighlighter: SyntaxHighlighter {
    private static let assignmentPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:(export)[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*(=)[ \t]*(.*)$"#
    )

    let language: SyntaxLanguage = .dotenv

    func expandedHighlightRange(
        for editedRange: NSRange,
        editContext: SyntaxHighlightEditContext?,
        in text: NSString
    ) -> NSRange {
        text.lineRange(for: editedRange.clamped(toLength: text.length))
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        let text = textStorage.string as NSString
        let targetRange = (range ?? NSRange(location: 0, length: text.length)).clamped(toLength: text.length)
        guard targetRange.length > 0 else { return }

        let scanRange = text.lineRange(for: targetRange)
        var location = scanRange.location
        let end = scanRange.upperBound
        while location < end {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = lineContentsRange(lineRange, in: text)
            highlightLine(
                text.substring(with: contentRange) as NSString,
                offset: contentRange.location,
                targetRange: targetRange,
                textStorage: textStorage,
                theme: theme
            )
            guard lineRange.upperBound > location else { break }
            location = lineRange.upperBound
        }
    }

    private func highlightLine(
        _ line: NSString,
        offset: Int,
        targetRange: NSRange,
        textStorage: NSTextStorage,
        theme: SyntaxTheme
    ) {
        let lineRange = NSRange(location: 0, length: line.length)
        var firstCharacter = 0
        while firstCharacter < line.length, isHorizontalWhitespace(line.character(at: firstCharacter)) {
            firstCharacter += 1
        }
        if firstCharacter < line.length, line.character(at: firstCharacter) == 35 {
            apply(.comment, range: NSRange(location: firstCharacter, length: line.length - firstCharacter), offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)
            return
        }

        guard let match = Self.assignmentPattern.firstMatch(in: line as String, range: lineRange) else { return }
        let exportRange = match.range(at: 1)
        if exportRange.location != NSNotFound {
            apply(.keyword, range: exportRange, offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)
        }
        apply(.propertyKey, range: match.range(at: 2), offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)
        apply(.operator, range: match.range(at: 3), offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)

        let valueRange = match.range(at: 4)
        let commentStart = inlineCommentStart(in: line, range: valueRange)
        let stringRange = NSRange(
            location: valueRange.location,
            length: (commentStart ?? valueRange.upperBound) - valueRange.location
        )
        apply(.string, range: stringRange, offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)
        highlightVariables(in: line, range: stringRange, offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)
        if let commentStart {
            apply(.comment, range: NSRange(location: commentStart, length: line.length - commentStart), offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)
        }
    }

    private func inlineCommentStart(in text: NSString, range: NSRange) -> Int? {
        var quote: unichar = 0
        var index = range.location
        while index < range.upperBound {
            let character = text.character(at: index)
            if quote == 34, character == 92 {
                index = min(index + 2, range.upperBound)
                continue
            }
            if quote != 0 {
                if character == quote { quote = 0 }
            } else if character == 34 || character == 39 {
                quote = character
            } else if character == 35,
                      index == range.location || isHorizontalWhitespace(text.character(at: index - 1)) {
                return index
            }
            index += 1
        }
        return nil
    }

    private func highlightVariables(
        in text: NSString,
        range: NSRange,
        offset: Int,
        targetRange: NSRange,
        textStorage: NSTextStorage,
        theme: SyntaxTheme
    ) {
        var quote: unichar = 0
        var index = range.location
        while index < range.upperBound {
            let character = text.character(at: index)
            if quote == 34, character == 92 {
                index = min(index + 2, range.upperBound)
                continue
            }
            if quote != 0 {
                if character == quote {
                    quote = 0
                } else if quote == 34, character == 36,
                          let end = variableEnd(in: text, at: index, before: range.upperBound) {
                    apply(.variable, range: NSRange(location: index, length: end - index), offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)
                    index = end
                    continue
                }
            } else if character == 34 || character == 39 {
                quote = character
            } else if character == 36,
                      let end = variableEnd(in: text, at: index, before: range.upperBound) {
                apply(.variable, range: NSRange(location: index, length: end - index), offset: offset, targetRange: targetRange, textStorage: textStorage, theme: theme)
                index = end
                continue
            }
            index += 1
        }
    }

    private func variableEnd(in text: NSString, at index: Int, before end: Int) -> Int? {
        // ponytail: colors simple references only; handle dotenv modifiers if users need them.
        let braced = index + 1 < end && text.character(at: index + 1) == 123
        let nameStart = index + (braced ? 2 : 1)
        guard nameStart < end, isIdentifierStart(text.character(at: nameStart)) else { return nil }
        var nameEnd = nameStart + 1
        while nameEnd < end, isIdentifierCharacter(text.character(at: nameEnd)) {
            nameEnd += 1
        }
        guard !braced || (nameEnd < end && text.character(at: nameEnd) == 125) else { return nil }
        return braced ? nameEnd + 1 : nameEnd
    }

    private func lineContentsRange(_ lineRange: NSRange, in text: NSString) -> NSRange {
        var end = lineRange.upperBound
        while end > lineRange.location {
            let character = text.character(at: end - 1)
            guard character == 10 || character == 13 else { break }
            end -= 1
        }
        return NSRange(location: lineRange.location, length: end - lineRange.location)
    }

    private func apply(
        _ role: SyntaxColorRole,
        range: NSRange,
        offset: Int,
        targetRange: NSRange,
        textStorage: NSTextStorage,
        theme: SyntaxTheme
    ) {
        let absoluteRange = NSRange(location: range.location + offset, length: range.length)
        textStorage.applyForegroundColor(theme.color(for: role), range: NSIntersectionRange(absoluteRange, targetRange))
    }

    private func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 32 || character == 9
    }

    private func isIdentifierStart(_ character: unichar) -> Bool {
        character == 95 || (65...90).contains(character) || (97...122).contains(character)
    }

    private func isIdentifierCharacter(_ character: unichar) -> Bool {
        isIdentifierStart(character) || (48...57).contains(character)
    }
}
