import Foundation

// SQL dialects (PL/pgSQL, T-SQL, MySQL) defeat a single grammar, so SQL is tokenized lexically, as IDEs do.
enum SQLSyntaxLexer {
    typealias Token = TreeSitterHighlightWork.Token

    static func tokens(in text: NSString) -> [Token] {
        var units = [unichar](repeating: 0, count: text.length)
        text.getCharacters(&units, range: NSRange(location: 0, length: text.length))
        var lexer = Lexer(units: units)
        lexer.run(from: 0, to: units.count)
        return lexer.tokens
    }

    /// Widens `edited` (new-text coordinates) to every token that differs from the previous pass.
    static func dirtyRange(old: [Token], new: [Token], edited: NSRange, delta: Int) -> NSRange {
        var prefix = 0
        while prefix < old.count, prefix < new.count, NSMaxRange(new[prefix].range) <= edited.location,
              old[prefix].range == new[prefix].range, old[prefix].role == new[prefix].role {
            prefix += 1
        }
        var oldEnd = old.count, newEnd = new.count
        while oldEnd > prefix, newEnd > prefix, new[newEnd - 1].range.location >= NSMaxRange(edited),
              old[oldEnd - 1].range.location + delta == new[newEnd - 1].range.location,
              old[oldEnd - 1].range.length == new[newEnd - 1].range.length,
              old[oldEnd - 1].role == new[newEnd - 1].role {
            oldEnd -= 1
            newEnd -= 1
        }
        var range = edited
        for token in new[prefix..<newEnd] { range = NSUnionRange(range, token.range) }
        for token in old[prefix..<oldEnd] {
            let location = token.range.location >= edited.location ? token.range.location + delta : token.range.location
            range = NSUnionRange(range, NSRange(location: max(0, location), length: token.range.length))
        }
        return range
    }
}

private struct Lexer {
    let units: [unichar]
    var tokens: [TreeSitterHighlightWork.Token] = []
    private var previousWord: String?
    private var expectsType = false

    init(units: [unichar]) {
        self.units = units
    }

    mutating func run(from start: Int, to end: Int) {
        var index = start
        while index < end {
            let unit = units[index]
            let next = index + 1 < end ? units[index + 1] : 0
            if isSpace(unit) {
                index += 1
            } else if unit == ascii("-"), next == ascii("-") {
                var stop = index
                while stop < end, units[stop] != 10, units[stop] != 13 { stop += 1 }
                emit(index, stop, .comment, significant: false)
                index = stop
            } else if unit == ascii("/"), next == ascii("*") {
                let stop = blockCommentEnd(from: index, to: end)
                emit(index, stop, .comment, significant: false)
                index = stop
            } else if unit == ascii("'") {
                let stop = quotedEnd(from: index, to: end, closing: unit)
                emit(index, stop, .string)
                index = stop
            } else if unit == ascii("\"") || unit == ascii("`")
                        || (unit == ascii("[") && !isWordUnit(at: index - 1) && previous(index) != ascii(")")) {
                let stop = quotedEnd(from: index, to: end, closing: unit == ascii("[") ? ascii("]") : unit)
                emit(index, stop, .propertyKey)
                index = stop
            } else if unit == ascii("$"), let delimiterEnd = dollarDelimiterEnd(from: index, to: end) {
                index = dollarQuoted(from: index, delimiterEnd: delimiterEnd, to: end)
            } else if unit == ascii(":"), next == ascii(":") {
                emit(index, index + 2, .operator)
                expectsType = true
                index += 2
            } else if (unit == ascii(":") || unit == ascii("$") || unit == ascii("@")) && !isWordUnit(at: index - 1)
                        && previous(index) != ascii(":") {
                var nameStart = index + 1
                if unit == ascii("@"), next == ascii("@") { nameStart += 1 }
                guard nameStart < end, isWordUnit(at: nameStart) else {
                    emit(index, index + 1, .operator)
                    index += 1
                    continue
                }
                let stop = wordEnd(from: nameStart, to: end)
                emit(index, stop, .variable)
                index = stop
            } else if unit == ascii("?"), !isWordUnit(at: index - 1), !isWordUnit(at: index + 1) {
                emit(index, index + 1, .variable)
                index += 1
            } else if isDigit(unit) || (unit == ascii(".") && isDigit(next) && !isWordUnit(at: index - 1)) {
                let stop = numberEnd(from: index, to: end)
                emit(index, stop, .variable)
                index = stop
            } else if isWordUnit(at: index) {
                let stop = wordEnd(from: index, to: end)
                classifyWord(index, stop, end)
                index = stop
            } else {
                emit(index, index + 1, operators.contains(unit) ? .operator : nil)
                index += 1
            }
        }
    }

    private mutating func classifyWord(_ start: Int, _ stop: Int, _ end: Int) {
        let word = String(utf16CodeUnits: Array(units[start..<stop]), count: stop - start).uppercased()
        var after = stop
        while after < end, isSpace(units[after]) { after += 1 }
        let role: SyntaxColorRole?
        if expectsType || SQLKeywords.types.contains(word) {
            role = .builtin
        } else if SQLKeywords.keywords.contains(word) {
            role = .keyword
        } else if after < end, units[after] == ascii("(") {
            role = .builtin
        } else {
            role = nil
        }
        emit(start, stop, role)
        previousWord = word
    }

    /// Function and DO bodies are code, so only their delimiters are styled as strings.
    private mutating func dollarQuoted(from start: Int, delimiterEnd: Int, to end: Int) -> Int {
        let delimiter = units[start..<delimiterEnd]
        var close = delimiterEnd
        while close + delimiter.count <= end, !units[close..<(close + delimiter.count)].elementsEqual(delimiter) {
            close += 1
        }
        let isCode = previousWord == "DO" || previousWord == "AS"
        guard close + delimiter.count <= end else {
            emit(start, end, .string)
            return end
        }
        let stop = close + delimiter.count
        guard isCode else {
            emit(start, stop, .string)
            return stop
        }
        emit(start, delimiterEnd, .string)
        previousWord = nil
        run(from: delimiterEnd, to: close)
        emit(close, stop, .string)
        return stop
    }

    private mutating func emit(_ start: Int, _ stop: Int, _ role: SyntaxColorRole?, significant: Bool = true) {
        if significant {
            expectsType = false
            previousWord = nil
        }
        guard let role, stop > start else { return }
        if let last = tokens.last, last.role == role, NSMaxRange(last.range) == start {
            tokens[tokens.count - 1] = .init(range: NSRange(location: last.range.location, length: stop - last.range.location), role: role)
        } else {
            tokens.append(.init(range: NSRange(location: start, length: stop - start), role: role))
        }
    }

    private func blockCommentEnd(from start: Int, to end: Int) -> Int {
        var depth = 0
        var index = start
        while index < end {
            if index + 1 < end, units[index] == ascii("/"), units[index + 1] == ascii("*") {
                depth += 1
                index += 2
            } else if index + 1 < end, units[index] == ascii("*"), units[index + 1] == ascii("/") {
                depth -= 1
                index += 2
                if depth == 0 { return index }
            } else {
                index += 1
            }
        }
        return end
    }

    private func quotedEnd(from start: Int, to end: Int, closing: unichar) -> Int {
        var index = start + 1
        while index < end {
            if units[index] == closing {
                if index + 1 < end, units[index + 1] == closing { index += 2 } else { return index + 1 }
            } else if closing == ascii("'"), units[index] == ascii("\\"), index + 1 < end {
                index += 2
            } else {
                index += 1
            }
        }
        return end
    }

    private func dollarDelimiterEnd(from start: Int, to end: Int) -> Int? {
        guard !isWordUnit(at: start - 1) else { return nil }
        var index = start + 1
        if index < end, units[index] != ascii("$") {
            guard isLetter(units[index]) || units[index] == ascii("_") else { return nil }
            while index < end, isWordUnit(at: index), units[index] != ascii("$") { index += 1 }
        }
        return index < end && units[index] == ascii("$") ? index + 1 : nil
    }

    private func wordEnd(from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, isWordUnit(at: index) { index += 1 }
        return index
    }

    private func numberEnd(from start: Int, to end: Int) -> Int {
        var index = start
        while index < end {
            let unit = units[index]
            if isWordUnit(at: index) || unit == ascii(".") {
                index += 1
            } else if (unit == ascii("+") || unit == ascii("-")), index > start,
                      units[index - 1] == ascii("e") || units[index - 1] == ascii("E"), isDigit(units[start]) {
                index += 1
            } else {
                break
            }
        }
        return index
    }

    private func previous(_ index: Int) -> unichar { index > 0 ? units[index - 1] : 0 }

    private func isWordUnit(at index: Int) -> Bool {
        guard index >= 0, index < units.count else { return false }
        let unit = units[index]
        return isLetter(unit) || isDigit(unit) || unit == ascii("_") || unit == ascii("$") || unit >= 0x80
    }

    private func isLetter(_ unit: unichar) -> Bool { (unit | 0x20) >= ascii("a") && (unit | 0x20) <= ascii("z") || unit >= 0x80 }
    private func isDigit(_ unit: unichar) -> Bool { unit >= ascii("0") && unit <= ascii("9") }
    private func isSpace(_ unit: unichar) -> Bool { unit == 32 || (unit >= 9 && unit <= 13) || unit == 0xA0 }
    private func ascii(_ character: Unicode.Scalar) -> unichar { unichar(character.value) }

    private let operators = Set("=<>!~+-*/%|&^:;.()[]#@".utf16)
}
