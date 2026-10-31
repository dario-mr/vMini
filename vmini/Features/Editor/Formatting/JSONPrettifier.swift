import Foundation

enum JSONPrettifier {
    struct FormattingError: LocalizedError {
        let message: String
        let characterIndex: Int

        var errorDescription: String? {
            message
        }
    }

    private enum JSONValue {
        case object([(String, JSONValue)])
        case array([JSONValue])
        case string(String)
        case number(String)
        case bool(Bool)
        case null
    }

    private struct Parser {
        let characters: [Character]
        var index = 0

        mutating func parse() throws -> JSONValue {
            skipWhitespace()
            let value = try parseValue()
            skipWhitespace()

            guard isAtEnd else {
                throw error("Unexpected trailing content at character \(index + 1).")
            }

            return value
        }

        private var isAtEnd: Bool {
            index >= characters.count
        }

        private mutating func parseValue() throws -> JSONValue {
            guard let character = currentCharacter else {
                throw error("Unexpected end of JSON input.")
            }

            switch character {
            case "{":
                return try parseObject()
            case "[":
                return try parseArray()
            case "\"":
                return .string(try parseString())
            case "t":
                try consumeLiteral("true")
                return .bool(true)
            case "f":
                try consumeLiteral("false")
                return .bool(false)
            case "n":
                try consumeLiteral("null")
                return .null
            case "-", "0"..."9":
                return .number(try parseNumber())
            default:
                throw error("Unexpected character '\(character)' at character \(index + 1).")
            }
        }

        private mutating func parseObject() throws -> JSONValue {
            try consume("{")
            skipWhitespace()

            var pairs: [(String, JSONValue)] = []
            if try consumeIfPresent("}") {
                return .object(pairs)
            }

            while true {
                skipWhitespace()
                guard currentCharacter == "\"" else {
                    throw error("Expected a string key at character \(index + 1).")
                }

                let key = try parseString()
                skipWhitespace()
                try consume(":")
                skipWhitespace()
                let value = try parseValue()
                pairs.append((key, value))
                skipWhitespace()

                if try consumeIfPresent("}") {
                    return .object(pairs)
                }

                try consume(",")
                skipWhitespace()
            }
        }

        private mutating func parseArray() throws -> JSONValue {
            try consume("[")
            skipWhitespace()

            var values: [JSONValue] = []
            if try consumeIfPresent("]") {
                return .array(values)
            }

            while true {
                values.append(try parseValue())
                skipWhitespace()

                if try consumeIfPresent("]") {
                    return .array(values)
                }

                try consume(",")
                skipWhitespace()
            }
        }

        private mutating func parseString() throws -> String {
            try consume("\"")
            var result = ""

            while let character = currentCharacter {
                advance()

                switch character {
                case "\"":
                    return result
                case "\\":
                    result.append(try parseEscapeSequence())
                default:
                    guard !character.isNewline else {
                        throw error("Unescaped newline in string at character \(index).")
                    }
                    result.append(character)
                }
            }

            throw error("Unterminated string literal.")
        }

        private mutating func parseEscapeSequence() throws -> String {
            guard let character = currentCharacter else {
                throw error("Incomplete escape sequence at end of input.")
            }

            advance()

            switch character {
            case "\"":
                return "\""
            case "\\":
                return "\\"
            case "/":
                return "/"
            case "b":
                return "\u{08}"
            case "f":
                return "\u{0C}"
            case "n":
                return "\n"
            case "r":
                return "\r"
            case "t":
                return "\t"
            case "u":
                return try parseUnicodeEscape()
            default:
                throw error("Invalid escape sequence '\\\(character)' at character \(index).")
            }
        }

        private mutating func parseUnicodeEscape() throws -> String {
            let scalarValue = try parseHexQuad()

            if (0xD800...0xDBFF).contains(scalarValue) {
                let highSurrogate = scalarValue
                try consume("\\")
                try consume("u")
                let lowSurrogate = try parseHexQuad()
                guard (0xDC00...0xDFFF).contains(lowSurrogate) else {
                    throw error("Invalid low surrogate in unicode escape at character \(index).")
                }

                let high = highSurrogate - 0xD800
                let low = lowSurrogate - 0xDC00
                let combined = 0x10000 + ((high << 10) | low)
                guard let scalar = UnicodeScalar(combined) else {
                    throw error("Invalid unicode scalar in escape sequence.")
                }
                return String(scalar)
            }

            guard let scalar = UnicodeScalar(scalarValue) else {
                throw error("Invalid unicode scalar in escape sequence.")
            }
            return String(scalar)
        }

        private mutating func parseHexQuad() throws -> UInt32 {
            var value: UInt32 = 0

            for _ in 0..<4 {
                guard let character = currentCharacter, let digit = character.hexDigitValue else {
                    throw error("Expected 4 hexadecimal digits in unicode escape at character \(index + 1).")
                }

                value = (value << 4) | UInt32(digit)
                advance()
            }

            return value
        }

        private mutating func parseNumber() throws -> String {
            let start = index

            if currentCharacter == "-" {
                advance()
            }

            guard let character = currentCharacter else {
                throw error("Incomplete number at end of input.")
            }

            if character == "0" {
                advance()
            } else if character.isNumber {
                while currentCharacter?.isNumber == true {
                    advance()
                }
            } else {
                throw error("Invalid number at character \(index + 1).")
            }

            if currentCharacter == "." {
                advance()
                let fractionStart = index
                while currentCharacter?.isNumber == true {
                    advance()
                }
                guard index > fractionStart else {
                    throw error("Expected digits after decimal point at character \(index + 1).")
                }
            }

            if currentCharacter == "e" || currentCharacter == "E" {
                advance()
                if currentCharacter == "+" || currentCharacter == "-" {
                    advance()
                }

                let exponentStart = index
                while currentCharacter?.isNumber == true {
                    advance()
                }
                guard index > exponentStart else {
                    throw error("Expected exponent digits at character \(index + 1).")
                }
            }

            return String(characters[start..<index])
        }

        private mutating func consumeLiteral(_ literal: String) throws {
            for expected in literal {
                try consume(expected)
            }
        }

        private mutating func consume(_ expected: Character) throws {
            guard currentCharacter == expected else {
                let found = currentCharacter.map(String.init) ?? "end of input"
                throw error("Expected '\(expected)' at character \(index + 1), found \(found).")
            }
            advance()
        }

        private mutating func consumeIfPresent(_ expected: Character) throws -> Bool {
            guard currentCharacter == expected else {
                return false
            }
            advance()
            return true
        }

        private mutating func skipWhitespace() {
            while currentCharacter?.isWhitespace == true {
                advance()
            }
        }

        private var currentCharacter: Character? {
            isAtEnd ? nil : characters[index]
        }

        private mutating func advance() {
            index += 1
        }

        private func error(_ message: String) -> FormattingError {
            FormattingError(message: message, characterIndex: index)
        }
    }

    private static let indentUnit = "  "

    static func prettify(_ candidate: String) throws -> String {
        var parser = Parser(characters: Array(candidate))
        let json = try parser.parse()
        return stringify(json, indentLevel: 0)
    }

    private static func stringify(_ value: JSONValue, indentLevel: Int) -> String {
        switch value {
        case let .object(object):
            return formatObject(object, indentLevel: indentLevel)
        case let .array(array):
            return formatArray(array, indentLevel: indentLevel)
        case let .string(string):
            return quote(string)
        case let .number(number):
            return number
        case let .bool(boolean):
            return boolean ? "true" : "false"
        case .null:
            return "null"
        }
    }

    private static func formatObject(_ object: [(String, JSONValue)], indentLevel: Int) -> String {
        guard !object.isEmpty else {
            return "{}"
        }

        let currentIndent = String(repeating: indentUnit, count: indentLevel)
        let childIndent = String(repeating: indentUnit, count: indentLevel + 1)
        let contents = object.map { key, value in
            "\(childIndent)\(quote(key)): \(stringify(value, indentLevel: indentLevel + 1))"
        }.joined(separator: ",\n")
        return "{\n\(contents)\n\(currentIndent)}"
    }

    private static func formatArray(_ array: [JSONValue], indentLevel: Int) -> String {
        guard !array.isEmpty else {
            return "[]"
        }

        let currentIndent = String(repeating: indentUnit, count: indentLevel)
        let childIndent = String(repeating: indentUnit, count: indentLevel + 1)
        let contents = array
            .map { "\(childIndent)\(stringify($0, indentLevel: indentLevel + 1))" }
            .joined(separator: ",\n")
        return "[\n\(contents)\n\(currentIndent)]"
    }

    private static func quote(_ string: String) -> String {
        var escaped = "\""

        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x08:
                escaped.append("\\b")
            case 0x09:
                escaped.append("\\t")
            case 0x0A:
                escaped.append("\\n")
            case 0x0C:
                escaped.append("\\f")
            case 0x0D:
                escaped.append("\\r")
            case 0x22:
                escaped.append("\\\"")
            case 0x5C:
                escaped.append("\\\\")
            case 0x00...0x1F:
                escaped.append(String(format: "\\u%04X", scalar.value))
            default:
                escaped.append(String(scalar))
            }
        }

        escaped.append("\"")
        return escaped
    }
}
