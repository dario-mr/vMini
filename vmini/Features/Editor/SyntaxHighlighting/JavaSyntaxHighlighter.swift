import AppKit

@MainActor
final class JavaSyntaxHighlighter: SyntaxHighlighter {
    private struct Token {
        let range: NSRange
        let role: SyntaxColorRole
    }

    // shortcut: contextual keywords are styled by spelling, refine with parser context if false positives matter.
    private static let keywords: Set<String> = [
        "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const",
        "continue", "default", "do", "double", "else", "enum", "exports", "extends", "false", "final",
        "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int", "interface",
        "long", "module", "native", "new", "null", "open", "opens", "package", "permits", "private",
        "protected", "provides", "public", "record", "requires", "return", "sealed", "short", "static",
        "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "to", "transient", "true",
        "try", "uses", "var", "void", "volatile", "when", "while", "with", "yield", "_",
    ]

    // shortcut: only common JDK types are styled, expand this list when broader API coverage is needed.
    private static let builtins: Set<String> = [
        "ArrayList", "Boolean", "Byte", "Character", "Class", "Collection", "Double", "Enum", "Exception",
        "Float", "HashMap", "Integer", "Iterable", "List", "Long", "Map", "Math", "Number", "Object",
        "Optional", "Record", "RuntimeException", "Set", "Short", "String", "StringBuilder", "StringBuffer",
        "System", "Thread", "Throwable", "Void",
    ]

    private static let nonSealedKeyword = Array("non-sealed")
    private static let operatorCharacters: Set<Character> = [
        "=", "+", "-", "*", "/", "%", "!", "<", ">", "&", "|", "?", "^", "~", ".", ":",
        ";", "(", ")", "{", "}", "[", "]", ",", "@",
    ]
    private static let multilineTokenBoundaryCharacters: Set<Character> = ["/", "*", "\"", "'", "\n", "\r"]

    let language: SyntaxLanguage = .java

    func expandedHighlightRange(
        for editedRange: NSRange,
        editContext: SyntaxHighlightEditContext?,
        in text: NSString
    ) -> NSRange {
        guard let editContext else {
            return NSRange(location: 0, length: text.length)
        }

        if [editContext.replacedText, editContext.replacementString].contains(where: { value in
            value.contains(where: { Self.multilineTokenBoundaryCharacters.contains($0) })
        }) {
            return NSRange(location: 0, length: text.length)
        }

        return text.lineRange(for: editedRange.clamped(toLength: text.length))
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

        for token in tokens(in: textStorage.string) {
            let visibleRange = NSIntersectionRange(token.range, targetRange)
            if visibleRange.length > 0 {
                textStorage.applyForegroundColor(theme.color(for: token.role), range: visibleRange)
            }
        }
    }

    private func tokens(in text: String) -> [Token] {
        let characterIndex = SyntaxCharacterIndex(text)
        let characters = characterIndex.characters
        var tokens: [Token] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                let end = indexAfterLineComment(in: characters, from: index)
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .comment))
                index = end
            } else if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                let end = indexAfterBlockComment(in: characters, from: index)
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .comment))
                index = end
            } else if character == "\"" || character == "'" {
                let isTextBlock = character == "\"" && index + 2 < characters.count
                    && characters[index + 1] == "\"" && characters[index + 2] == "\""
                let end = indexAfterQuotedLiteral(in: characters, from: index, isTextBlock: isTextBlock)
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .string))
                index = end
            } else if character.isNumber {
                let end = numberTokenEnd(in: characters, from: index)
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .variable))
                index = end
            } else if isNonSealedKeyword(at: index, in: characters) {
                let end = index + Self.nonSealedKeyword.count
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .keyword))
                index = end
            } else if isIdentifierStart(character) {
                let end = identifierEnd(in: characters, from: index)
                let identifier = String(characters[index..<end])
                if Self.keywords.contains(identifier) {
                    tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .keyword))
                } else if Self.builtins.contains(identifier) {
                    tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .builtin))
                }
                index = end
            } else if character == "@" {
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: index + 1), role: .operator))
                let nameStart = index + 1
                let nameEnd = annotationTypeEnd(in: characters, from: nameStart)
                let annotationName = nameEnd > nameStart ? String(characters[nameStart..<nameEnd]) : ""
                if nameEnd > nameStart, annotationName != "interface" {
                    tokens.append(Token(range: characterIndex.nsRange(start: nameStart, end: nameEnd), role: .builtin))
                    index = nameEnd
                } else {
                    index = nameStart
                }
            } else if Self.operatorCharacters.contains(character) {
                var end = index + 1
                while end < characters.count, Self.operatorCharacters.contains(characters[end]) {
                    end += 1
                }
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .operator))
                index = end
            } else {
                index += 1
            }
        }

        return tokens
    }

    private func indexAfterLineComment(in characters: [Character], from start: Int) -> Int {
        var current = start
        while current < characters.count, characters[current] != "\n", characters[current] != "\r" {
            current += 1
        }
        return current
    }

    private func indexAfterBlockComment(in characters: [Character], from start: Int) -> Int {
        var current = start + 2
        while current + 1 < characters.count {
            if characters[current] == "*", characters[current + 1] == "/" {
                return current + 2
            }
            current += 1
        }
        return characters.count
    }

    private func indexAfterQuotedLiteral(in characters: [Character], from start: Int, isTextBlock: Bool) -> Int {
        let quote = characters[start]
        var current = start + (isTextBlock ? 3 : 1)

        while current < characters.count {
            if isTextBlock, current + 2 < characters.count,
               characters[current] == "\"", characters[current + 1] == "\"", characters[current + 2] == "\"" {
                return current + 3
            }
            if !isTextBlock, characters[current] == quote {
                return current + 1
            }
            if characters[current] == "\\" {
                current += min(2, characters.count - current)
            } else if !isTextBlock, characters[current] == "\n" || characters[current] == "\r" {
                return current
            } else {
                current += 1
            }
        }

        return characters.count
    }

    private func numberTokenEnd(in characters: [Character], from start: Int) -> Int {
        var current = start

        if current + 1 < characters.count, characters[current] == "0",
           characters[current + 1] == "x" || characters[current + 1] == "X" {
            current += 2
            while current < characters.count, isHexDigitOrSeparator(characters[current]) { current += 1 }
            if current < characters.count, characters[current] == "." {
                current += 1
                while current < characters.count, isHexDigitOrSeparator(characters[current]) { current += 1 }
            }
            if current < characters.count, characters[current] == "p" || characters[current] == "P" {
                current = exponentEnd(in: characters, from: current)
            }
        } else if current + 1 < characters.count, characters[current] == "0",
                  characters[current + 1] == "b" || characters[current + 1] == "B" {
            current += 2
            while current < characters.count,
                  characters[current] == "0" || characters[current] == "1" || characters[current] == "_" {
                current += 1
            }
        } else {
            while current < characters.count, isDecimalDigitOrSeparator(characters[current]) { current += 1 }
            if current < characters.count, characters[current] == "." {
                current += 1
                while current < characters.count, isDecimalDigitOrSeparator(characters[current]) { current += 1 }
            }
            if current < characters.count, characters[current] == "e" || characters[current] == "E" {
                let exponentStart = current
                let exponentEnd = self.exponentEnd(in: characters, from: current)
                if exponentEnd > exponentStart + 1 { current = exponentEnd }
            }
        }

        if current < characters.count, "lLfFdD".contains(characters[current]) {
            current += 1
        }
        return current
    }

    private func exponentEnd(in characters: [Character], from start: Int) -> Int {
        var current = start + 1
        if current < characters.count, characters[current] == "+" || characters[current] == "-" {
            current += 1
        }
        let digitsStart = current
        while current < characters.count, isDecimalDigitOrSeparator(characters[current]) { current += 1 }
        return current == digitsStart ? start : current
    }

    private func isHexDigitOrSeparator(_ character: Character) -> Bool {
        "0123456789abcdefABCDEF_".contains(character)
    }

    private func isDecimalDigitOrSeparator(_ character: Character) -> Bool {
        character.isNumber || character == "_"
    }

    private func isNonSealedKeyword(at index: Int, in characters: [Character]) -> Bool {
        let end = index + Self.nonSealedKeyword.count
        guard end <= characters.count, Array(characters[index..<end]) == Self.nonSealedKeyword else { return false }
        return end == characters.count || !isIdentifierCharacter(characters[end])
    }

    private func identifierEnd(in characters: [Character], from start: Int) -> Int {
        var current = start + 1
        while current < characters.count, isIdentifierCharacter(characters[current]) {
            current += 1
        }
        return current
    }

    private func annotationTypeEnd(in characters: [Character], from start: Int) -> Int {
        guard start < characters.count, isIdentifierStart(characters[start]) else { return start }

        var end = identifierEnd(in: characters, from: start)
        while end + 1 < characters.count, characters[end] == ".", isIdentifierStart(characters[end + 1]) {
            end = identifierEnd(in: characters, from: end + 1)
        }
        return end
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character == "$" || character.isLetter
    }

    private func isIdentifierCharacter(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }
}
