import AppKit

@MainActor
final class KotlinSyntaxHighlighter: SyntaxHighlighter {
    private struct Token {
        let range: NSRange
        let role: SyntaxColorRole
    }

    private static let keywords: Set<String> = [
        "abstract", "actual", "annotation", "as", "break", "by", "catch", "class", "companion", "const",
        "constructor", "context", "continue", "crossinline", "data", "delegate", "do", "dynamic", "else",
        "enum", "expect", "external", "field", "file", "final", "finally", "for", "fun",
        "get", "if", "import", "in", "infix", "init", "inline", "inner", "interface",
        "internal", "is", "lateinit", "noinline", "object", "open", "operator", "out",
        "override", "package", "param", "private", "property", "protected", "public", "receiver",
        "reified", "return", "sealed", "set", "setparam", "suspend", "tailrec", "this", "throw",
        "super", "try", "typealias", "typeof", "val", "var", "vararg", "when", "where", "while",
        "false", "null", "true",
    ]

    private static let builtins: Set<String> = [
        "Any", "Array", "Boolean", "Byte", "Char", "Double", "Float", "Int", "List", "Long",
        "Map", "MutableList", "MutableMap", "MutableSet", "Nothing", "Pair", "Sequence", "Set",
        "Short", "String", "Triple", "Unit",
    ]

    private static let operatorCharacters: Set<Character> = [
        "=", "+", "-", "*", "/", "%", "!", "<", ">", "&", "|", "?", "^", "~", ".", ":",
        ";", "(", ")", "{", "}", "[", "]", ",", "@",
    ]

    private static let multilineTokenBoundaryCharacters: Set<Character> = ["/", "*", "\"", "'", "\n", "\r"]

    let language: SyntaxLanguage = .kotlin

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
                let end = indexAfterString(in: characters, from: index)
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .string))
                index = end
            } else if character.isNumber {
                let end = numberTokenEnd(in: characters, from: index)
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .variable))
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
            } else if character == "`" {
                index = indexAfterEscapedIdentifier(in: characters, from: index)
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
        var depth = 1
        var current = start + 2
        while current < characters.count {
            if current + 1 < characters.count, characters[current] == "/", characters[current + 1] == "*" {
                depth += 1
                current += 2
            } else if current + 1 < characters.count, characters[current] == "*", characters[current + 1] == "/" {
                depth -= 1
                current += 2
                if depth == 0 { return current }
            } else {
                current += 1
            }
        }
        return characters.count
    }

    private func indexAfterString(in characters: [Character], from start: Int) -> Int {
        let quote = characters[start]
        let isRawString = quote == "\"" && start + 2 < characters.count &&
            characters[start + 1] == "\"" && characters[start + 2] == "\""
        let delimiterLength = isRawString ? 3 : 1
        var current = start + delimiterLength

        while current < characters.count {
            if isRawString, current + 2 < characters.count,
               characters[current] == "\"", characters[current + 1] == "\"", characters[current + 2] == "\"" {
                return current + 3
            }
            if !isRawString, characters[current] == quote {
                return current + 1
            }
            if !isRawString, characters[current] == "\\" {
                current += min(2, characters.count - current)
            } else if !isRawString, (characters[current] == "\n" || characters[current] == "\r") {
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
           (characters[current + 1] == "x" || characters[current + 1] == "X") {
            current += 2
            while current < characters.count,
                  (characters[current].isNumber || "abcdefABCDEF_".contains(characters[current])) {
                current += 1
            }
        } else if current + 1 < characters.count, characters[current] == "0",
                  (characters[current + 1] == "b" || characters[current + 1] == "B") {
            current += 2
            while current < characters.count,
                  (characters[current] == "0" || characters[current] == "1" || characters[current] == "_") {
                current += 1
            }
        } else {
            while current < characters.count, (characters[current].isNumber || characters[current] == "_") {
                current += 1
            }

            if current + 1 < characters.count, characters[current] == ".",
               characters[current + 1].isNumber {
                current += 1
                while current < characters.count, (characters[current].isNumber || characters[current] == "_") {
                    current += 1
                }
            }

            if current < characters.count, (characters[current] == "e" || characters[current] == "E") {
                let exponentStart = current
                current += 1
                if current < characters.count, (characters[current] == "+" || characters[current] == "-") {
                    current += 1
                }
                let digitStart = current
                while current < characters.count, (characters[current].isNumber || characters[current] == "_") {
                    current += 1
                }
                if current == digitStart { current = exponentStart }
            }
        }

        if current < characters.count, "uU".contains(characters[current]) {
            current += 1
            if current < characters.count, "lL".contains(characters[current]) { current += 1 }
        } else if current < characters.count, "lLfF".contains(characters[current]) {
            current += 1
        }

        return current
    }

    private func identifierEnd(in characters: [Character], from start: Int) -> Int {
        var current = start + 1
        while current < characters.count, isIdentifierCharacter(characters[current]) {
            current += 1
        }
        return current
    }

    private func indexAfterEscapedIdentifier(in characters: [Character], from start: Int) -> Int {
        var current = start + 1
        while current < characters.count, characters[current] != "`", characters[current] != "\n", characters[current] != "\r" {
            current += 1
        }
        return current < characters.count && characters[current] == "`" ? current + 1 : current
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private func isIdentifierCharacter(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }
}
