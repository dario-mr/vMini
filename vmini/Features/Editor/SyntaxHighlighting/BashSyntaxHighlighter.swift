import AppKit

@MainActor
final class BashSyntaxHighlighter: SyntaxHighlighter {
    private struct Token {
        let range: NSRange
        let role: SyntaxColorRole
    }

    private static let keywords: Set<String> = [
        "if", "then", "else", "elif", "fi",
        "for", "while", "until", "do", "done",
        "case", "esac", "function", "in", "select",
    ]

    private static let builtins: Set<String> = [
        "export", "local", "readonly", "unset",
        "source", "alias", "unalias", "return",
        "exit", "cd", ".", "set", "shift",
        "echo", "nohup", "pgrep"
    ]

    private static let twoCharacterOperators: Set<String> = [
        "||", "&&", ">>", "<<", "|&", ";;",
    ]

    private static let oneCharacterOperators: Set<Character> = [
        "|", "&", ";", "=", "(", ")", "{", "}", "[", "]", "<", ">",
    ]

    let language: SyntaxLanguage = .bash

    func expandedHighlightRange(for editedRange: NSRange, in text: NSString) -> NSRange {
        let lineRange = text.lineRange(for: editedRange.clamped(toLength: text.length))
        let fullText = text as String

        for token in tokenize(fullText) where token.role == .string || token.role == .variable {
            if token.range.intersects(lineRange),
               fullText[token.range.swiftRange(in: fullText)].contains("\n") {
                return token.range
            }
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
        let fullText = textStorage.string
        let targetRange = (range ?? NSRange(location: 0, length: (fullText as NSString).length))
            .clamped(toLength: (fullText as NSString).length)

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
        var tokens: [Token] = []
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "#" && isCommentStart(in: characters, at: index) {
                let end = indexAfterComment(in: characters, from: index)
                tokens.append(Token(range: nsRange(start: index, end: end, in: text), role: .comment))
                index = end
                continue
            }

            if character == "'" {
                let end = indexAfterSingleQuotedString(in: characters, from: index)
                tokens.append(Token(range: nsRange(start: index, end: end, in: text), role: .string))
                index = end
                continue
            }

            if character == "\"" {
                let (stringTokens, end) = doubleQuotedStringTokens(in: characters, from: index, text: text)
                tokens.append(contentsOf: stringTokens)
                index = end
                continue
            }

            if character == "$", let end = variableTokenEnd(in: characters, from: index) {
                tokens.append(Token(range: nsRange(start: index, end: end, in: text), role: .variable))
                index = end
                continue
            }

            if let operatorLength = operatorLength(in: characters, at: index) {
                tokens.append(Token(range: nsRange(start: index, end: index + operatorLength, in: text), role: .operator))
                index += operatorLength
                continue
            }

            if character.isShellWordStart {
                let end = indexAfterWord(in: characters, from: index)
                let word = String(characters[index..<end])
                if Self.keywords.contains(word) {
                    tokens.append(Token(range: nsRange(start: index, end: end, in: text), role: .keyword))
                } else if Self.builtins.contains(word) {
                    tokens.append(Token(range: nsRange(start: index, end: end, in: text), role: .builtin))
                }
                index = end
                continue
            }

            if character == ".", isStandaloneDotBuiltin(in: characters, at: index) {
                tokens.append(Token(range: nsRange(start: index, end: index + 1, in: text), role: .builtin))
                index += 1
                continue
            }

            index += 1
        }

        return tokens
    }

    private func isCommentStart(in characters: [Character], at index: Int) -> Bool {
        guard index < characters.count else {
            return false
        }

        guard index == 0 else {
            let previous = characters[index - 1]
            return previous.isWhitespace || Self.oneCharacterOperators.contains(previous)
        }

        return true
    }

    private func indexAfterComment(in characters: [Character], from index: Int) -> Int {
        var current = index
        while current < characters.count, characters[current] != "\n" {
            current += 1
        }
        return current
    }

    private func indexAfterSingleQuotedString(in characters: [Character], from index: Int) -> Int {
        var current = index + 1
        while current < characters.count {
            if characters[current] == "'" {
                return current + 1
            }
            current += 1
        }
        return characters.count
    }

    private func indexAfterDoubleQuotedString(in characters: [Character], from index: Int) -> Int {
        var current = index + 1
        while current < characters.count {
            if characters[current] == "\"", !isEscaped(in: characters, at: current) {
                return current + 1
            }
            current += 1
        }
        return characters.count
    }

    private func doubleQuotedStringTokens(in characters: [Character], from index: Int, text: String) -> ([Token], Int) {
        var current = index + 1
        var tokens = [Token(range: nsRange(start: index, end: indexAfterDoubleQuotedString(in: characters, from: index), in: text), role: .string)]
        let stringEnd = indexAfterDoubleQuotedString(in: characters, from: index)

        while current < stringEnd - 1 {
            if characters[current] == "$", let variableEnd = variableTokenEnd(in: characters, from: current), variableEnd <= stringEnd {
                tokens.append(Token(range: nsRange(start: current, end: variableEnd, in: text), role: .variable))
                current = variableEnd
                continue
            }

            current += 1
        }

        return (tokens, stringEnd)
    }

    private func variableTokenEnd(in characters: [Character], from index: Int) -> Int? {
        let nextIndex = index + 1
        guard nextIndex < characters.count else {
            return nil
        }

        let next = characters[nextIndex]
        if next == "{" {
            return indexAfterBalancedBraces(in: characters, from: index)
        }

        if next == "(" {
            return indexAfterCommandSubstitution(in: characters, from: index)
        }

        if next.isShellVariableCharacter || next.isShellSpecialVariable {
            var current = nextIndex + 1
            while current < characters.count, characters[current].isShellVariableCharacter {
                current += 1
            }
            return current
        }

        return nil
    }

    private func indexAfterBalancedBraces(in characters: [Character], from index: Int) -> Int {
        var current = index + 2
        var depth = 1

        while current < characters.count {
            if characters[current] == "{" {
                depth += 1
            } else if characters[current] == "}" {
                depth -= 1
                if depth == 0 {
                    return current + 1
                }
            }
            current += 1
        }

        return characters.count
    }

    private func indexAfterCommandSubstitution(in characters: [Character], from index: Int) -> Int {
        var current = index + 2
        var depth = 1

        while current < characters.count {
            let character = characters[current]
            if character == "'", let stringEnd = optionalAdvance(indexAfterSingleQuotedString(in: characters, from: current), from: current) {
                current = stringEnd
                continue
            }

            if character == "\"", let stringEnd = optionalAdvance(indexAfterDoubleQuotedString(in: characters, from: current), from: current) {
                current = stringEnd
                continue
            }

            if character == "$", current + 1 < characters.count, characters[current + 1] == "(" {
                depth += 1
                current += 2
                continue
            }

            if character == ")" {
                depth -= 1
                if depth == 0 {
                    return current + 1
                }
            }

            current += 1
        }

        return characters.count
    }

    private func operatorLength(in characters: [Character], at index: Int) -> Int? {
        if index + 1 < characters.count {
            let pair = String(characters[index...(index + 1)])
            if Self.twoCharacterOperators.contains(pair) {
                return 2
            }
        }

        if Self.oneCharacterOperators.contains(characters[index]) {
            return 1
        }

        return nil
    }

    private func indexAfterWord(in characters: [Character], from index: Int) -> Int {
        var current = index + 1
        while current < characters.count, characters[current].isShellWordCharacter {
            current += 1
        }
        return current
    }

    private func isStandaloneDotBuiltin(in characters: [Character], at index: Int) -> Bool {
        let previousIsBoundary = index == 0 || characters[index - 1].isWhitespace || Self.oneCharacterOperators.contains(characters[index - 1])
        let nextIsBoundary = index + 1 == characters.count || characters[index + 1].isWhitespace
        return previousIsBoundary && nextIsBoundary
    }

    private func isEscaped(in characters: [Character], at index: Int) -> Bool {
        guard index > 0 else {
            return false
        }

        var backslashCount = 0
        var current = index - 1
        while true {
            guard characters[current] == "\\" else {
                break
            }
            backslashCount += 1
            guard current > 0 else {
                break
            }
            current -= 1
        }

        return backslashCount.isMultiple(of: 2) == false
    }

    private func optionalAdvance(_ end: Int, from start: Int) -> Int? {
        end > start ? end : nil
    }

    private func nsRange(start: Int, end: Int, in text: String) -> NSRange {
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        return NSRange(startIndex..<endIndex, in: text)
    }
}

private extension Character {
    var isShellWordStart: Bool {
        isLetter || self == "_"
    }

    var isShellWordCharacter: Bool {
        isLetter || isNumber || self == "_" || self == "-"
    }

    var isShellVariableCharacter: Bool {
        isLetter || isNumber || self == "_"
    }

    var isShellSpecialVariable: Bool {
        ["@", "*", "#", "?", "-", "$", "!"].contains(self)
    }
}

private extension NSRange {
    func swiftRange(in text: String) -> Range<String.Index> {
        Range(self, in: text) ?? text.startIndex..<text.startIndex
    }
}
