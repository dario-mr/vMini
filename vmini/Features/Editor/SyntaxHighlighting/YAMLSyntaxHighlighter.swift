import AppKit

@MainActor
final class YAMLSyntaxHighlighter: SyntaxHighlighter {
    private struct Token {
        let range: NSRange
        let role: SyntaxColorRole
    }

    let language: SyntaxLanguage = .yaml

    func expandedHighlightRange(for editedRange: NSRange, in text: NSString) -> NSRange {
        text.lineRange(for: editedRange.clamped(toLength: text.length))
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
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
        let line = text.substring(with: lineRange)
        let characters = Array(line)
        guard characters.isEmpty == false else {
            return []
        }

        let commentStart = commentStartIndex(in: characters)
        let contentEnd = commentStart ?? characters.count
        var tokens: [Token] = []
        var current = 0

        while current < contentEnd {
            let character = characters[current]

            if character.isWhitespace {
                current += 1
                continue
            }

            if Self.flowOperatorCharacters.contains(character) {
                tokens.append(token(start: current, end: current + 1, baseLocation: lineRange.location, role: .operator))
                current += 1
                continue
            }

            if character == "-", isSequenceMarker(in: characters, at: current, contentEnd: contentEnd) {
                tokens.append(token(start: current, end: current + 1, baseLocation: lineRange.location, role: .operator))
                current += 1
                continue
            }

            if character == "\"" || character == "'" {
                let end = indexAfterQuotedScalar(in: characters, from: current)
                let role: SyntaxColorRole = isMappingKey(in: characters, scalarEnd: end, contentEnd: contentEnd)
                    ? .propertyKey
                    : .string
                tokens.append(token(start: current, end: end, baseLocation: lineRange.location, role: role))
                current = end
                continue
            }

            if let keyRange = mappingKeyRange(in: characters, from: current, contentEnd: contentEnd) {
                tokens.append(token(start: keyRange.start, end: keyRange.end, baseLocation: lineRange.location, role: .propertyKey))
                current = keyRange.end
                continue
            }

            if let end = numberTokenEnd(in: characters, from: current, contentEnd: contentEnd) {
                tokens.append(token(start: current, end: end, baseLocation: lineRange.location, role: .variable))
                current = end
                continue
            }

            if let end = bareScalarEnd(in: characters, from: current, contentEnd: contentEnd) {
                let scalar = String(characters[current..<end]).lowercased()
                if Self.keywordLiterals.contains(scalar) {
                    tokens.append(token(start: current, end: end, baseLocation: lineRange.location, role: .keyword))
                } else {
                    tokens.append(token(start: current, end: end, baseLocation: lineRange.location, role: .string))
                }
                current = end
                continue
            }

            current += 1
        }

        if let commentStart {
            tokens.append(
                Token(
                    range: NSRange(location: lineRange.location + commentStart, length: characters.count - commentStart),
                    role: .comment
                )
            )
        }

        return tokens
    }

    private func commentStartIndex(in characters: [Character]) -> Int? {
        var current = 0

        while current < characters.count {
            let character = characters[current]
            if character == "\"" || character == "'" {
                current = indexAfterQuotedScalar(in: characters, from: current)
                continue
            }

            if character == "#" {
                let previous = current > 0 ? characters[current - 1] : nil
                if previous == nil || previous?.isWhitespace == true {
                    return current
                }
            }

            current += 1
        }

        return nil
    }

    private func isSequenceMarker(in characters: [Character], at index: Int, contentEnd: Int) -> Bool {
        guard index < contentEnd, characters[index] == "-" else {
            return false
        }

        let previous = index > 0 ? characters[index - 1] : nil
        let next = index + 1 < contentEnd ? characters[index + 1] : nil
        let previousAllowsSequence = previous == nil || previous?.isWhitespace == true || (previous.map { Self.flowOperatorCharacters.contains($0) } ?? false)
        let nextAllowsSequence = next == nil || next?.isWhitespace == true || (next.map { Self.flowOperatorCharacters.contains($0) } ?? false)

        return previousAllowsSequence && nextAllowsSequence
    }

    private func indexAfterQuotedScalar(in characters: [Character], from start: Int) -> Int {
        let quote = characters[start]
        var current = start + 1

        while current < characters.count {
            if characters[current] == quote {
                if quote == "'" || isEscaped(in: characters, at: current) == false {
                    return current + 1
                }
            }
            current += 1
        }

        return characters.count
    }

    private func isEscaped(in characters: [Character], at index: Int) -> Bool {
        guard index > 0 else {
            return false
        }

        var current = index - 1
        var backslashCount = 0

        while characters[current] == "\\" {
            backslashCount += 1
            guard current > 0 else {
                break
            }
            current -= 1
        }

        return backslashCount.isMultiple(of: 2) == false
    }

    private func isMappingKey(in characters: [Character], scalarEnd: Int, contentEnd: Int) -> Bool {
        var current = scalarEnd
        while current < contentEnd, characters[current].isWhitespace {
            current += 1
        }

        return current < contentEnd && isMappingSeparator(in: characters, at: current, contentEnd: contentEnd)
    }

    private func mappingKeyRange(in characters: [Character], from start: Int, contentEnd: Int) -> (start: Int, end: Int)? {
        guard isPlainScalarCharacter(characters[start]) else {
            return nil
        }

        var current = start
        while current < contentEnd {
            let character = characters[current]
            if character == ":" {
                let trimmedEnd = trimTrailingWhitespace(in: characters, from: start, to: current)
                guard trimmedEnd > start, isMappingSeparator(in: characters, at: current, contentEnd: contentEnd) else {
                    return nil
                }
                return (start, trimmedEnd)
            }

            if character == "\"" || character == "'" || character == "#" || Self.flowOperatorCharacters.contains(character) {
                return nil
            }

            current += 1
        }

        return nil
    }

    private func trimTrailingWhitespace(in characters: [Character], from start: Int, to end: Int) -> Int {
        var current = end
        while current > start, characters[current - 1].isWhitespace {
            current -= 1
        }
        return current
    }

    private func isMappingSeparator(in characters: [Character], at colonIndex: Int, contentEnd: Int) -> Bool {
        guard characters[colonIndex] == ":" else {
            return false
        }

        let nextIndex = colonIndex + 1
        if nextIndex >= contentEnd {
            return true
        }

        let next = characters[nextIndex]
        return next.isWhitespace || Self.flowOperatorCharacters.contains(next)
    }

    private func numberTokenEnd(in characters: [Character], from start: Int, contentEnd: Int) -> Int? {
        guard start < contentEnd else {
            return nil
        }

        let previous = start > 0 ? characters[start - 1] : nil
        let previousAllowsNumber = previous == nil || previous?.isWhitespace == true || (previous.map { Self.flowOperatorCharacters.contains($0) } ?? false)
        guard previousAllowsNumber else {
            return nil
        }

        var current = start
        if characters[current] == "-" {
            current += 1
        }

        guard current < contentEnd else {
            return nil
        }

        let integerStart = current
        while current < contentEnd, characters[current].isNumber {
            current += 1
        }
        guard current > integerStart else {
            return nil
        }

        if current < contentEnd, characters[current] == "." {
            current += 1
            let fractionStart = current
            while current < contentEnd, characters[current].isNumber {
                current += 1
            }
            guard current > fractionStart else {
                return nil
            }
        }

        if current < contentEnd, characters[current] == "e" || characters[current] == "E" {
            current += 1
            if current < contentEnd, characters[current] == "+" || characters[current] == "-" {
                current += 1
            }

            let exponentStart = current
            while current < contentEnd, characters[current].isNumber {
                current += 1
            }
            guard current > exponentStart else {
                return nil
            }
        }

        let next = current < contentEnd ? characters[current] : nil
        let nextAllowsNumber = next == nil || next?.isWhitespace == true || (next.map { Self.flowOperatorCharacters.contains($0) } ?? false)
        guard nextAllowsNumber else {
            return nil
        }

        return current
    }

    private func bareScalarEnd(in characters: [Character], from start: Int, contentEnd: Int) -> Int? {
        guard isPlainScalarCharacter(characters[start]) else {
            return nil
        }

        var current = start
        while current < contentEnd {
            let character = characters[current]
            if character.isWhitespace || character == "#" {
                break
            }

            if Self.flowOperatorCharacters.contains(character) {
                if character == ":", isMappingSeparator(in: characters, at: current, contentEnd: contentEnd) == false {
                    current += 1
                    continue
                }
                break
            }

            current += 1
        }

        return current > start ? current : nil
    }

    private func isPlainScalarCharacter(_ character: Character) -> Bool {
        !character.isWhitespace && character != "#" && character != "\"" && character != "'" && Self.flowOperatorCharacters.contains(character) == false
    }

    private func token(start: Int, end: Int, baseLocation: Int, role: SyntaxColorRole) -> Token {
        Token(range: NSRange(location: baseLocation + start, length: max(end - start, 0)), role: role)
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

    private static let keywordLiterals: Set<String> = [
        "true", "false", "null", "~", "yes", "no", "on", "off",
    ]

    private static let flowOperatorCharacters: Set<Character> = [
        "{", "}", "[", "]", ",", ":", "?",
    ]
}
