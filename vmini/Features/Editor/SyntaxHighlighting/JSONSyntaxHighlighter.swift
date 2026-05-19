import AppKit

@MainActor
final class JSONSyntaxHighlighter: SyntaxHighlighter {
    private struct Token {
        let range: NSRange
        let role: SyntaxColorRole
    }

    let language: SyntaxLanguage = .json

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
        let fullText = textStorage.string
        let nsText = fullText as NSString
        let targetRange = (range ?? NSRange(location: 0, length: nsText.length)).clamped(toLength: nsText.length)

        guard targetRange.length > 0 else {
            return
        }

        for token in tokenize(fullText) {
            let visibleRange = NSIntersectionRange(token.range, targetRange)
            guard visibleRange.length > 0 else {
                continue
            }

            textStorage.applyForegroundColor(theme.color(for: token.role), range: visibleRange)
        }
    }

    private func tokenize(_ text: String) -> [Token] {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                let end = indexAfterString(in: characters, from: index)
                let role: SyntaxColorRole = isObjectKey(in: characters, stringEnd: end) ? .propertyKey : .string
                tokens.append(Token(range: nsRange(start: index, end: end, in: text), role: role))
                index = end
                continue
            }

            if let end = numberTokenEnd(in: characters, from: index) {
                tokens.append(Token(range: nsRange(start: index, end: end, in: text), role: .variable))
                index = end
                continue
            }

            if let literal = literalToken(in: characters, from: index, text: text) {
                tokens.append(literal.token)
                index = literal.end
                continue
            }

            if Self.operatorCharacters.contains(character) {
                tokens.append(Token(range: nsRange(start: index, end: index + 1, in: text), role: .operator))
                index += 1
                continue
            }

            index += 1
        }

        return tokens
    }

    private func indexAfterString(in characters: [Character], from start: Int) -> Int {
        var current = start + 1

        while current < characters.count {
            if characters[current] == "\"", !isEscaped(in: characters, at: current) {
                return current + 1
            }
            current += 1
        }

        return characters.count
    }

    private func isEscaped(in characters: [Character], at index: Int) -> Bool {
        guard index > 0 else {
            return false
        }

        var backslashCount = 0
        var current = index - 1
        while current >= 0, characters[current] == "\\" {
            backslashCount += 1
            guard current > 0 else { break }
            current -= 1
        }

        return backslashCount.isMultiple(of: 2) == false
    }

    private func isObjectKey(in characters: [Character], stringEnd: Int) -> Bool {
        var current = stringEnd
        while current < characters.count, characters[current].isWhitespace {
            current += 1
        }
        return current < characters.count && characters[current] == ":"
    }

    private func numberTokenEnd(in characters: [Character], from start: Int) -> Int? {
        guard start < characters.count else {
            return nil
        }

        var current = start
        if characters[current] == "-" {
            current += 1
        }

        guard current < characters.count else {
            return nil
        }

        if characters[current] == "0" {
            current += 1
        } else if characters[current].isNumber {
            repeat {
                current += 1
            } while current < characters.count && characters[current].isNumber
        } else {
            return nil
        }

        if current < characters.count, characters[current] == "." {
            current += 1
            let fractionStart = current
            while current < characters.count, characters[current].isNumber {
                current += 1
            }
            guard current > fractionStart else {
                return nil
            }
        }

        if current < characters.count, characters[current] == "e" || characters[current] == "E" {
            current += 1
            if current < characters.count, characters[current] == "+" || characters[current] == "-" {
                current += 1
            }

            let exponentStart = current
            while current < characters.count, characters[current].isNumber {
                current += 1
            }
            guard current > exponentStart else {
                return nil
            }
        }

        return current > start ? current : nil
    }

    private func literalToken(in characters: [Character], from start: Int, text: String) -> (token: Token, end: Int)? {
        for literal in Self.keywordLiterals {
            guard matches(literal, in: characters, at: start) else {
                continue
            }

            let end = start + literal.count
            return (Token(range: nsRange(start: start, end: end, in: text), role: .keyword), end)
        }

        return nil
    }

    private func matches(_ literal: String, in characters: [Character], at start: Int) -> Bool {
        let literalCharacters = Array(literal)
        guard start + literalCharacters.count <= characters.count else {
            return false
        }

        for offset in literalCharacters.indices where characters[start + offset] != literalCharacters[offset] {
            return false
        }

        let previous = start > 0 ? characters[start - 1] : nil
        let nextIndex = start + literalCharacters.count
        let next = nextIndex < characters.count ? characters[nextIndex] : nil
        return !isIdentifierCharacter(previous) && !isIdentifierCharacter(next)
    }

    private func isIdentifierCharacter(_ character: Character?) -> Bool {
        guard let character else {
            return false
        }

        return character.isLetter || character.isNumber || character == "_"
    }

    private func nsRange(start: Int, end: Int, in text: String) -> NSRange {
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        return NSRange(startIndex..<endIndex, in: text)
    }

    private static let keywordLiterals = ["true", "false", "null"]
    private static let operatorCharacters: Set<Character> = ["{", "}", "[", "]", ":", ","]
}
