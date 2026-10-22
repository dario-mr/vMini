import AppKit

@MainActor
final class SQLSyntaxHighlighter: SyntaxHighlighter {
    private struct Token {
        let range: NSRange
        let role: SyntaxColorRole
    }

    private static let keywords: Set<String> = [
        "add", "all", "alter", "and", "any", "as", "asc", "begin", "between", "by", "case", "cast",
        "check", "column", "commit", "constraint", "create", "cross", "current_date", "current_time",
        "current_timestamp", "database", "default", "delete", "desc", "distinct", "drop", "else", "end",
        "except", "exists", "false", "fetch", "for", "foreign", "from", "full", "function", "grant",
        "group", "having", "in", "index", "inner", "insert", "intersect", "into", "is", "join", "key",
        "left", "like", "limit", "not", "null", "offset", "on", "or", "order", "outer", "primary",
        "procedure", "references", "returning", "right", "rollback", "row", "schema", "select", "set",
        "table", "then", "true", "truncate", "union", "unique", "update", "using", "values", "view",
        "when", "where", "with",
    ]

    private static let dataTypes: Set<String> = [
        "bigint", "binary", "bit", "blob", "boolean", "char", "character", "date", "datetime", "decimal",
        "double", "float", "int", "integer", "json", "nchar", "numeric", "nvarchar", "real", "smallint",
        "text", "time", "timestamp", "uuid", "varbinary", "varchar",
    ]

    private static let functions: Set<String> = [
        "avg", "btrim", "coalesce", "concat", "count", "date_add", "date_sub", "floor", "greatest", "ifnull",
        "least", "length", "lower", "max", "min", "nullif", "now", "round", "substring", "sum", "trim",
        "upper",
    ]

    // shortcut: dialect-specific syntax is not parsed; add rules when a supported SQL dialect needs them.
    private static let lexicalBoundaryCharacters: Set<Character> = ["-", "/", "*", "'", "\"", "`", "[", "]", "$", "@", ":", "?"]
    private static let operatorCharacters: Set<Character> = ["=", "<", ">", "!", "+", "-", "*", "/", "%", "|", "&", "^", "~", ":", "(", ")", ",", ".", ";"]

    let language: SyntaxLanguage = .sql

    func expandedHighlightRange(
        for editedRange: NSRange,
        editContext: SyntaxHighlightEditContext?,
        in text: NSString
    ) -> NSRange {
        let fullRange = NSRange(location: 0, length: text.length)
        guard let editContext else { return fullRange }

        let clampedRange = editedRange.clamped(toLength: text.length)
        let lineRange = text.lineRange(for: clampedRange)
        let nearbyStart = max(0, clampedRange.location - 2)
        let nearbyEnd = min(text.length, clampedRange.upperBound + 2)
        let nearbyText = text.substring(with: NSRange(location: nearbyStart, length: nearbyEnd - nearbyStart))
        let changedText = editContext.replacedText + editContext.replacementString
        if changedText.contains(where: Self.lexicalBoundaryCharacters.contains)
            || nearbyText.contains(where: Self.lexicalBoundaryCharacters.contains)
            || changedText.contains(where: \.isNewline) {
            return fullRange
        }

        for token in tokens(in: text as String)
        where (token.role == .comment || token.role == .string || token.role == .propertyKey)
            && token.range.intersects(lineRange)
            && text.substring(with: token.range).contains(where: \.isNewline) {
            return token.range
        }

        return lineRange
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
        let index = SyntaxCharacterIndex(text)
        let characters = index.characters
        var tokens: [Token] = []
        var current = 0

        while current < characters.count {
            let character = characters[current]
            let next = current + 1 < characters.count ? characters[current + 1] : nil

            if character.isWhitespace {
                current += 1
            } else if character == "-", next == "-" {
                let end = indexAfterLine(in: characters, from: current)
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .comment))
                current = end
            } else if character == "/", next == "*" {
                let end = indexAfterBlockComment(in: characters, from: current)
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .comment))
                current = end
            } else if character == "`", next == "`", current + 2 < characters.count, characters[current + 2] == "`" {
                current = indexAfterLine(in: characters, from: current)
            } else if character == "'" {
                let end = indexAfterQuotedToken(in: characters, from: current, closing: "'")
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .string))
                current = end
            } else if character == "\"" || character == "`" || character == "[" {
                let closing: Character = character == "[" ? "]" : character
                let end = indexAfterQuotedToken(in: characters, from: current, closing: closing)
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .propertyKey))
                current = end
            } else if character == "$", let end = dollarQuotedStringEnd(in: characters, from: current) {
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .string))
                current = end
            } else if character == "?" {
                tokens.append(Token(range: index.nsRange(start: current, end: current + 1), role: .variable))
                current += 1
            } else if character == "@", let end = variableEnd(in: characters, from: current, prefixLength: next == "@" ? 2 : 1) {
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .variable))
                current = end
            } else if character == ":", next != ":", current == 0 || characters[current - 1] != ":",
                      let end = variableEnd(in: characters, from: current, prefixLength: 1) {
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .variable))
                current = end
            } else if character == "$", let end = variableEnd(in: characters, from: current, prefixLength: 1) {
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .variable))
                current = end
            } else if character.isNumber {
                let end = numberEnd(in: characters, from: current)
                tokens.append(Token(range: index.nsRange(start: current, end: end), role: .variable))
                current = end
            } else if isIdentifierStart(character) {
                let end = identifierEnd(in: characters, from: current)
                let word = String(characters[current..<end])
                let normalized = word.lowercased()
                let nextSignificant = nextNonWhitespaceIndex(in: characters, from: end)
                let role: SyntaxColorRole?
                if Self.keywords.contains(normalized) {
                    role = .keyword
                } else if Self.dataTypes.contains(normalized)
                    || (Self.functions.contains(normalized) && nextSignificant < characters.count && characters[nextSignificant] == "(") {
                    role = .builtin
                } else {
                    role = nil
                }
                if let role {
                    tokens.append(Token(range: index.nsRange(start: current, end: end), role: role))
                }
                current = end
            } else if Self.operatorCharacters.contains(character) {
                tokens.append(Token(range: index.nsRange(start: current, end: current + 1), role: .operator))
                current += 1
            } else {
                current += 1
            }
        }

        return tokens
    }

    private func indexAfterLine(in characters: [Character], from start: Int) -> Int {
        var current = start
        while current < characters.count, characters[current] != "\n", characters[current] != "\r" {
            current += 1
        }
        return current
    }

    private func indexAfterBlockComment(in characters: [Character], from start: Int) -> Int {
        var current = start + 2
        var depth = 1
        while current + 1 < characters.count {
            if characters[current] == "/", characters[current + 1] == "*" {
                depth += 1
                current += 2
            } else if characters[current] == "*", characters[current + 1] == "/" {
                depth -= 1
                current += 2
                if depth == 0 { return current }
            } else {
                current += 1
            }
        }
        return characters.count
    }

    private func indexAfterQuotedToken(in characters: [Character], from start: Int, closing: Character) -> Int {
        var current = start + 1
        while current < characters.count {
            if characters[current] == closing {
                if current + 1 < characters.count, characters[current + 1] == closing {
                    current += 2
                } else {
                    return current + 1
                }
            } else if closing == "'", characters[current] == "\\", current + 1 < characters.count {
                current += 2
            } else {
                current += 1
            }
        }
        return characters.count
    }

    private func dollarQuotedStringEnd(in characters: [Character], from start: Int) -> Int? {
        var delimiterEnd = start + 1
        if delimiterEnd < characters.count, characters[delimiterEnd] != "$" {
            guard isIdentifierStart(characters[delimiterEnd]) else { return nil }
            delimiterEnd = identifierEnd(in: characters, from: delimiterEnd)
        }
        guard delimiterEnd < characters.count, characters[delimiterEnd] == "$" else { return nil }

        let delimiter = Array(characters[start...delimiterEnd])
        var current = delimiterEnd + 1
        while current + delimiter.count <= characters.count {
            if Array(characters[current..<(current + delimiter.count)]) == delimiter {
                return current + delimiter.count
            }
            current += 1
        }
        return characters.count
    }

    private func variableEnd(in characters: [Character], from start: Int, prefixLength: Int) -> Int? {
        let nameStart = start + prefixLength
        guard nameStart < characters.count,
              isIdentifierStart(characters[nameStart]) || characters[nameStart].isNumber else { return nil }

        var current = nameStart + 1
        while current < characters.count,
              isIdentifierCharacter(characters[current]) || characters[current].isNumber {
            current += 1
        }
        return current
    }

    private func numberEnd(in characters: [Character], from start: Int) -> Int {
        var current = start
        while current < characters.count, characters[current].isNumber || characters[current] == "_" {
            current += 1
        }

        if current + 1 < characters.count, characters[current] == ".", characters[current + 1].isNumber {
            current += 1
            while current < characters.count, characters[current].isNumber || characters[current] == "_" {
                current += 1
            }
        }

        if current < characters.count, characters[current] == "e" || characters[current] == "E" {
            var exponentEnd = current + 1
            if exponentEnd < characters.count, characters[exponentEnd] == "+" || characters[exponentEnd] == "-" {
                exponentEnd += 1
            }
            let exponentStart = exponentEnd
            while exponentEnd < characters.count, characters[exponentEnd].isNumber || characters[exponentEnd] == "_" {
                exponentEnd += 1
            }
            if exponentEnd > exponentStart { current = exponentEnd }
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

    private func nextNonWhitespaceIndex(in characters: [Character], from start: Int) -> Int {
        var current = start
        while current < characters.count, characters[current].isWhitespace {
            current += 1
        }
        return current
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private func isIdentifierCharacter(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber || character == "$"
    }
}
