import Foundation
import SwiftTreeSitter
import TreeSitterJava

struct JavaHighlightWork: Sendable {
    struct Token: Sendable {
        let range: NSRange
        let role: SyntaxColorRole
    }

    let range: NSRange
    let tokens: [Token]
}

// One parser per editor; its mutable tree never leaves this actor.
actor JavaSyntaxSession {
    private let parser = JavaSyntaxParser()
    private var revision: UInt64 = 0

    func highlight(
        text: String, range: NSRange?, edits: [SyntaxHighlightEditContext]?,
        baseRevision: UInt64, revision: UInt64
    ) -> JavaHighlightWork? {
        guard !Task.isCancelled, revision > self.revision else { return nil }
        if baseRevision != self.revision || edits == nil { parser.reset() }
        let work = parser.highlight(text: text, in: range, edits: edits ?? [])
        self.revision = revision
        return work
    }
}

final class JavaSyntaxParser {
    private let parser = Parser()
    private var tree: MutableTree?
    private var textLength = 0
    private var lineStarts = [0]

    init() {
        // The grammar and query are bundled, version-pinned application resources.
        try! parser.setLanguage(Self.language)
    }

    func reset() {
        tree = nil
        parser.reset()
    }

    func highlight(
        text: String, in requestedRange: NSRange?, edits: [SyntaxHighlightEditContext] = []
    ) -> JavaHighlightWork {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        guard source.length < Int(UInt32.max) / 2 else {
            reset()
            return JavaHighlightWork(range: fullRange, tokens: [])
        }
        var range = (requestedRange ?? fullRange).clamped(toLength: source.length)
        for edit in edits where tree != nil {
            guard apply(edit) else { reset(); break }
        }
        if tree == nil || textLength != source.length {
            reset()
            lineStarts = [0]
            for (offset, unit) in text.utf16.enumerated() where unit == 10 {
                lineStarts.append(offset + 1)
            }
        }
        let oldTree = tree
        // Read UTF-16 units directly: a parser chunk can split a surrogate pair or grapheme.
        tree = parser.parse(tree: oldTree) { byteOffset, _ in
            let location = byteOffset / 2
            let count = min(2_048, source.length - location)
            guard count > 0 else { return nil }
            var data = Data(count: count * 2)
            data.withUnsafeMutableBytes { bytes in
                source.getCharacters(bytes.bindMemory(to: UInt16.self).baseAddress!,
                                     range: NSRange(location: location, length: count))
            }
            return data
        }
        textLength = source.length
        guard let tree else { return JavaHighlightWork(range: fullRange, tokens: []) }
        if let oldTree {
            for change in tree.changedRanges(from: oldTree) {
                range = NSUnionRange(range, change.bytes.range).clamped(toLength: source.length)
            }
        }
        range = source.lineRange(for: range).clamped(toLength: source.length)
        let cursor = Self.query.execute(in: tree)
        cursor.setRange(range)
        var tokens: [JavaHighlightWork.Token] = []
        for match in cursor {
            for capture in match.captures {
                let tokenRange = NSIntersectionRange(capture.range, range)
                guard tokenRange.length > 0 else { continue }
                let role: SyntaxColorRole
                switch capture.name {
                case "word":
                    let word = source.substring(with: capture.range)
                    if Self.keywords.contains(word) { role = .keyword }
                    else if Self.builtins.contains(word) { role = .builtin }
                    else { continue }
                case "keyword": role = .keyword
                case "builtin": role = .builtin
                case "comment": role = .comment
                case "string": role = .string
                case "number": role = .variable
                default: role = .operator
                }
                tokens.append(.init(range: tokenRange, role: role))
            }
        }
        return JavaHighlightWork(range: range, tokens: tokens)
    }

    private func apply(_ edit: SyntaxHighlightEditContext) -> Bool {
        let range = edit.replacementRange
        let replacement = Array(edit.replacementString.utf16)
        guard range.location >= 0, range.length >= 0,
              range.location <= textLength, range.length <= textLength - range.location,
              range.length == edit.replacedText.utf16.count,
              textLength - range.length + replacement.count < Int(UInt32.max) / 2 else { return false }
        let start = point(at: range.location)
        let end = point(at: NSMaxRange(range))
        let newLineStarts = replacement.indices.filter { replacement[$0] == 10 }.map { range.location + $0 + 1 }
        let newEnd = Point(
            row: Int(start.row) + newLineStarts.count,
            column: newLineStarts.last.map { (range.location + replacement.count - $0) * 2 }
                ?? (Int(start.column) + replacement.count * 2)
        )
        tree?.edit(InputEdit(
            startByte: range.location * 2, oldEndByte: NSMaxRange(range) * 2,
            newEndByte: (range.location + replacement.count) * 2,
            startPoint: start, oldEndPoint: end, newEndPoint: newEnd
        ))
        let delta = replacement.count - range.length
        lineStarts = Array(lineStarts.prefix(Int(start.row) + 1)) + newLineStarts
            + lineStarts.dropFirst(Int(end.row) + 1).map { $0 + delta }
        textLength += delta
        return true
    }

    private func point(at offset: Int) -> Point {
        var lower = 0
        var upper = lineStarts.count
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= offset { lower = middle } else { upper = middle }
        }
        return Point(row: lower, column: (offset - lineStarts[lower]) * 2)
    }

    private static let language = Language(language: tree_sitter_java())
    private static let query = try! Query(language: language, data: Data(querySource.utf8))

    private static let querySource = #"""
    [(identifier) (type_identifier) (boolean_type) (integral_type) (floating_point_type)
     (void_type) (true) (false) (null_literal) (this) (super)] @word
    [(line_comment) (block_comment)] @comment
    [(string_literal) (character_literal)] @string
    [(hex_integer_literal) (decimal_integer_literal) (octal_integer_literal) (binary_integer_literal)
     (decimal_floating_point_literal) (hex_floating_point_literal)] @number
    (annotation name: (_) @builtin)
    (marker_annotation name: (_) @builtin)
    ["abstract" "assert" "break" "case" "catch" "class" "continue" "default" "do" "else"
     "enum" "exports" "extends" "final" "finally" "for" "if" "implements" "import" "instanceof"
     "interface" "module" "native" "new" "non-sealed" "open" "opens" "package" "permits"
     "private" "protected" "provides" "public" "requires" "record" "return" "sealed" "static"
     "strictfp" "switch" "synchronized" "throw" "throws" "to" "transient" "transitive" "try"
     "uses" "volatile" "when" "while" "with" "yield"] @keyword
    ["=" "+" "-" "*" "/" "%" "!" "<" ">" "&" "|" "?" "^" "~" "." ":" ";" "(" ")"
     "{" "}" "[" "]" "," "@" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^=" "==" "!=" "<=" ">="
     "&&" "||" "++" "--" "<<" ">>" ">>>" "<<=" ">>=" ">>>=" "->" "::"] @operator
    "@interface" @keyword
    """#

    // shortcut: contextual keywords keep their existing spelling-based colors; refine when needed.
    private static let keywords: Set<String> = [
        "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const",
        "continue", "default", "do", "double", "else", "enum", "exports", "extends", "false", "final",
        "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int", "interface",
        "long", "module", "native", "new", "null", "open", "opens", "package", "permits", "private",
        "protected", "provides", "public", "record", "requires", "return", "sealed", "short", "static",
        "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "to", "transient", "true",
        "try", "uses", "var", "void", "volatile", "when", "while", "with", "yield", "_",
    ]

    // shortcut: only common JDK types are styled, expand when broader API coverage is needed.
    private static let builtins: Set<String> = [
        "ArrayList", "Boolean", "Byte", "Character", "Class", "Collection", "Double", "Enum", "Exception",
        "Float", "HashMap", "Integer", "Iterable", "List", "Long", "Map", "Math", "Number", "Object",
        "Optional", "Record", "RuntimeException", "Set", "Short", "String", "StringBuilder", "StringBuffer",
        "System", "Thread", "Throwable", "Void",
    ]
}
