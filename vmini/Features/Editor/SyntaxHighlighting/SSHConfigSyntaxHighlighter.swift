import AppKit

@MainActor
final class SSHConfigSyntaxHighlighter: SyntaxHighlighter {
    private struct Token {
        let range: NSRange
        let role: SyntaxColorRole
    }

    let language: SyntaxLanguage = .sshconfig

    func expandedHighlightRange(for editedRange: NSRange, in text: NSString) -> NSRange {
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
        guard targetRange.length > 0 else {
            return
        }

        for token in tokens(in: text, targetRange: targetRange) {
            textStorage.applyForegroundColor(theme.color(for: token.role), range: token.range)
        }
    }

    private func tokens(in text: NSString, targetRange: NSRange) -> [Token] {
        var tokens: [Token] = []
        var location = 0

        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = visibleLineContentsRange(for: lineRange, text: text) ?? lineRange

            if contentRange.intersects(targetRange) {
                tokens.append(contentsOf: tokensForLine(in: text, lineRange: contentRange))
            }

            location = lineRange.upperBound
        }

        return tokens
    }

    private func tokensForLine(in text: NSString, lineRange: NSRange) -> [Token] {
        let line = text.substring(with: lineRange) as NSString
        let leadingWhitespace = leadingWhitespaceCount(in: line as String)
        guard leadingWhitespace < line.length else {
            return []
        }

        let firstContentLocation = lineRange.location + leadingWhitespace
        let firstCharacter = text.substring(with: NSRange(location: firstContentLocation, length: 1))
        if firstCharacter == "#" {
            return [Token(range: NSRange(location: firstContentLocation, length: lineRange.upperBound - firstContentLocation), role: .comment)]
        }

        let contentStart = leadingWhitespace
        var keywordEnd = contentStart
        while keywordEnd < line.length {
            let character = line.character(at: keywordEnd)
            guard let scalar = UnicodeScalar(character), !CharacterSet.whitespaces.contains(scalar) else {
                break
            }
            keywordEnd += 1
        }

        guard keywordEnd > contentStart else {
            return []
        }

        var tokens = [
            Token(
                range: NSRange(location: lineRange.location + contentStart, length: keywordEnd - contentStart),
                role: .keyword
            ),
        ]

        let valueStart = skipWhitespace(in: line, from: keywordEnd)
        if valueStart < line.length {
            tokens.append(
                Token(
                    range: NSRange(location: lineRange.location + valueStart, length: line.length - valueStart),
                    role: .string
                )
            )
        }

        return tokens
    }

    private func skipWhitespace(in line: NSString, from index: Int) -> Int {
        var current = index
        while current < line.length {
            let character = line.character(at: current)
            guard let scalar = UnicodeScalar(character), CharacterSet.whitespaces.contains(scalar) else {
                break
            }
            current += 1
        }
        return current
    }

    private func leadingWhitespaceCount(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private func visibleLineContentsRange(for lineRange: NSRange, text: NSString) -> NSRange? {
        guard lineRange.length > 0 else {
            return nil
        }

        var contentLength = lineRange.length
        let lastCharacter = text.character(at: lineRange.upperBound - 1)
        if let scalar = UnicodeScalar(lastCharacter), CharacterSet.newlines.contains(scalar) {
            contentLength -= 1
        }

        return NSRange(location: lineRange.location, length: max(contentLength, 0))
    }
}
