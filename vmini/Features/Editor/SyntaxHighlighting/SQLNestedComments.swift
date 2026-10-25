import Foundation

// The bundled SQL grammar stops at the first */. Mask nested comments without changing offsets.
enum SQLNestedComments {
    static func mask(in text: String) -> (source: NSString, ranges: [NSRange])? {
        guard text.contains("/*") else { return nil }
        let index = SyntaxCharacterIndex(text)
        let characters = index.characters
        var ranges: [NSRange] = []
        var current = 0
        while current < characters.count {
            let character = characters[current]
            let next = current + 1 < characters.count ? characters[current + 1] : nil
            if character == "-", next == "-" {
                while current < characters.count, !characters[current].isNewline { current += 1 }
            } else if character == "'" || character == "\"" || character == "`" || character == "[" {
                current = quotedEnd(in: characters, from: current, closing: character == "[" ? "]" : character)
            } else if character == "$", let end = dollarQuotedEnd(in: characters, from: current) {
                current = end
            } else if character == "/", next == "*" {
                let start = current
                var depth = 1
                var nested = false
                current += 2
                while current < characters.count, depth > 0 {
                    if current + 1 < characters.count, characters[current] == "/", characters[current + 1] == "*" {
                        depth += 1
                        nested = true
                        current += 2
                    } else if current + 1 < characters.count, characters[current] == "*", characters[current + 1] == "/" {
                        depth -= 1
                        current += 2
                    } else {
                        current += 1
                    }
                }
                if nested { ranges.append(index.nsRange(start: start, end: current)) }
            } else {
                current += 1
            }
        }
        guard !ranges.isEmpty else { return nil }
        let source = NSMutableString(string: text)
        for range in ranges {
            let units = source.substring(with: range).utf16.map { unit -> UInt16 in
                unit == 10 || unit == 13 ? unit : 32
            }
            source.replaceCharacters(in: range, with: String(decoding: units, as: UTF16.self))
        }
        return (source, ranges)
    }

    private static func quotedEnd(in characters: [Character], from start: Int, closing: Character) -> Int {
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

    private static func dollarQuotedEnd(in characters: [Character], from start: Int) -> Int? {
        // Dollar quotes cannot start inside an identifier.
        if start > 0, characters[start - 1].isLetter || characters[start - 1].isNumber || "_$".contains(characters[start - 1]) {
            return nil
        }
        var end = start + 1
        if end < characters.count, characters[end] != "$" {
            guard characters[end].isLetter || characters[end] == "_" else { return nil }
            while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
                end += 1
            }
        }
        guard end < characters.count, characters[end] == "$" else { return nil }
        let delimiter = characters[start...end]
        var current = end + 1
        while current + delimiter.count <= characters.count {
            if characters[current..<(current + delimiter.count)].elementsEqual(delimiter) {
                return current + delimiter.count
            }
            current += 1
        }
        return characters.count
    }
}
