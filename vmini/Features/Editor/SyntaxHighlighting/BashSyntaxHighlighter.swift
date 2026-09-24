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
    private static let multilineTokenBoundaryCharacters: Set<Character> = [
        "'", "\"", "\\", "$", "#", "(", ")", "{", "}",
    ]

    let language: SyntaxLanguage = .bash

    func expandedHighlightRange(
        for editedRange: NSRange,
        editContext: SyntaxHighlightEditContext?,
        in text: NSString
    ) -> NSRange {
        expandedHighlightRange(
            for: editedRange,
            cachedMultilineTokenRanges: multilineTokenRanges(in: text as String),
            in: text
        )
    }

    func expandedHighlightRange(
        for editedRange: NSRange,
        cachedMultilineTokenRanges: [NSRange],
        in text: NSString
    ) -> NSRange {
        let lineRange = text.lineRange(for: editedRange.clamped(toLength: text.length))
        return cachedMultilineTokenRanges.first(where: { $0.intersects(lineRange) }) ?? lineRange
    }

    func multilineTokenRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        return multilineTokenRanges(from: tokenize(text), in: nsText, offset: 0)
    }

    func updatedMultilineTokenRanges(
        _ ranges: [NSRange],
        cachedTextLength: Int,
        editContext: SyntaxHighlightEditContext,
        in currentText: NSString
    ) -> [NSRange]? {
        let replacedRange = editContext.replacementRange
        let replacedLength = (editContext.replacedText as NSString).length
        let replacementLength = (editContext.replacementString as NSString).length
        guard replacedRange.length == replacedLength,
              replacedRange.location <= cachedTextLength,
              replacedRange.upperBound <= cachedTextLength,
              currentText.length == cachedTextLength - replacedLength + replacementLength,
              !editMayChangeMultilineTokens(editContext, replacementLength: replacementLength, in: currentText) else {
            return nil
        }

        let delta = replacementLength - replacedLength
        return ranges.map { range in
            if range.upperBound <= replacedRange.location {
                return range
            }
            if range.location >= replacedRange.upperBound {
                return range.offsetBy(delta)
            }
            return NSRange(location: range.location, length: range.length + delta)
        }
    }

    private func editMayChangeMultilineTokens(
        _ editContext: SyntaxHighlightEditContext,
        replacementLength: Int,
        in currentText: NSString
    ) -> Bool {
        for text in [editContext.replacedText, editContext.replacementString] {
            if text.contains(where: {
                Self.multilineTokenBoundaryCharacters.contains($0) || $0 == "\n" || $0 == "\r"
            }) {
                return true
            }
        }

        let suffixLocation = editContext.replacementRange.location + replacementLength
        return suffixLocation < currentText.length
            && currentText.substring(with: NSRange(location: suffixLocation, length: 1)) == "#"
    }

    private func multilineTokenRanges(from tokens: [Token], in text: NSString, offset: Int) -> [NSRange] {
        tokens.compactMap { token in
            guard (token.role == .string || token.role == .variable),
                  text.range(of: "\n", options: [], range: token.range).location != NSNotFound else {
                return nil
            }
            return token.range.offsetBy(offset)
        }
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        highlight(
            textStorage: textStorage,
            in: range,
            baseFont: baseFont,
            theme: theme,
            registry: registry,
            onFullTextScan: nil
        )
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry,
        onFullTextScan: (([NSRange]) -> Void)?
    ) {
        let fullText = textStorage.string
        let targetRange = (range ?? NSRange(location: 0, length: (fullText as NSString).length))
            .clamped(toLength: (fullText as NSString).length)

        guard targetRange.length > 0 else {
            return
        }

        let nsText = fullText as NSString
        let localScanRange = nsText.lineRange(for: targetRange)
        let localText = nsText.substring(with: localScanRange)
        let tokens = tokenize(localText)

        if targetRange.location == 0, targetRange.length == nsText.length {
            onFullTextScan?(multilineTokenRanges(from: tokens, in: localText as NSString, offset: localScanRange.location))
        }

        for token in tokens {
            let visibleRange = NSIntersectionRange(token.range.offsetBy(localScanRange.location), targetRange)
            guard visibleRange.length > 0 else { continue }
            textStorage.applyForegroundColor(theme.color(for: token.role), range: visibleRange)
        }
    }

    private func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let characterIndex = SyntaxCharacterIndex(text)
        let characters = characterIndex.characters
        var index = 0
        var expectsCommand = true

        while index < characters.count {
            let character = characters[index]

            if character == "#" && isCommentStart(in: characters, at: index) {
                let end = indexAfterComment(in: characters, from: index)
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .comment))
                index = end
                continue
            }

            if character == "'" {
                let end = indexAfterSingleQuotedString(in: characters, from: index)
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .string))
                index = end
                continue
            }

            if character == "\"" {
                let (stringTokens, end) = doubleQuotedStringTokens(in: characters, from: index, characterIndex: characterIndex)
                tokens.append(contentsOf: stringTokens)
                index = end
                continue
            }

            if character == "$", let end = variableTokenEnd(in: characters, from: index) {
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .variable))
                index = end
                continue
            }

            if character == "-", let end = optionTokenEnd(in: characters, from: index) {
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .option))
                index = end
                continue
            }

            if let operatorLength = operatorLength(in: characters, at: index) {
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: index + operatorLength), role: .operator))
                expectsCommand = commandExpectationAfterOperator(
                    String(characters[index..<(index + operatorLength)]),
                    previousExpectation: expectsCommand
                )
                index += operatorLength
                continue
            }

            if character.isShellWordStart {
                let end = indexAfterWord(in: characters, from: index)
                let word = String(characters[index..<end])
                let nextCharacter = end < characters.count ? characters[end] : nil
                if Self.keywords.contains(word) {
                    tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .keyword))
                    expectsCommand = commandExpectationAfterKeyword(word)
                } else if Self.builtins.contains(word) {
                    tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .builtin))
                    expectsCommand = false
                } else if expectsCommand, nextCharacter != "=" {
                    tokens.append(Token(range: characterIndex.nsRange(start: index, end: end), role: .builtin))
                    expectsCommand = false
                }
                index = end
                continue
            }

            if character == ".", isStandaloneDotBuiltin(in: characters, at: index) {
                tokens.append(Token(range: characterIndex.nsRange(start: index, end: index + 1), role: .builtin))
                expectsCommand = false
                index += 1
                continue
            }

            if character == "\n" {
                expectsCommand = true
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

    private func doubleQuotedStringTokens(
        in characters: [Character],
        from index: Int,
        characterIndex: SyntaxCharacterIndex
    ) -> ([Token], Int) {
        var current = index + 1
        var tokens = [Token(range: characterIndex.nsRange(start: index, end: indexAfterDoubleQuotedString(in: characters, from: index)), role: .string)]
        let stringEnd = indexAfterDoubleQuotedString(in: characters, from: index)

        while current < stringEnd - 1 {
            if characters[current] == "$", let variableEnd = variableTokenEnd(in: characters, from: current), variableEnd <= stringEnd {
                tokens.append(Token(range: characterIndex.nsRange(start: current, end: variableEnd), role: .variable))
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

    private func optionTokenEnd(in characters: [Character], from index: Int) -> Int? {
        guard index + 1 < characters.count else {
            return nil
        }

        let next = characters[index + 1]
        guard next == "-" || next.isLetter || next.isNumber else {
            return nil
        }

        var current = index + 1
        while current < characters.count, characters[current].isShellOptionCharacter {
            current += 1
        }

        return current > index + 1 ? current : nil
    }

    private func commandExpectationAfterOperator(_ op: String, previousExpectation: Bool) -> Bool {
        switch op {
        case ";", ";;", "&&", "||", "|", "|&", "&", "(", "{":
            true
        case "=":
            previousExpectation
        default:
            false
        }
    }

    private func commandExpectationAfterKeyword(_ keyword: String) -> Bool {
        switch keyword {
        case "if", "then", "else", "elif", "while", "until", "do":
            true
        default:
            false
        }
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

    var isShellOptionCharacter: Bool {
        isLetter || isNumber || self == "-" || self == "_"
    }

    var isShellSpecialVariable: Bool {
        ["@", "*", "#", "?", "-", "$", "!"].contains(self)
    }
}

private extension NSRange {
    func swiftRange(in text: String) -> Range<String.Index> {
        Range(self, in: text) ?? text.startIndex..<text.startIndex
    }

    func offsetBy(_ offset: Int) -> NSRange {
        NSRange(location: location + offset, length: length)
    }
}
