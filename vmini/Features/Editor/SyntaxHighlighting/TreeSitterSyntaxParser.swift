import Foundation
import SwiftTreeSitter

struct TreeSitterHighlightWork: Sendable {
    struct Token: Sendable {
        let range: NSRange
        let role: SyntaxColorRole
    }

    let range: NSRange
    let tokens: [Token]
}

actor TreeSitterSyntaxSession {
    private let parser: TreeSitterSyntaxParser
    private var revision: UInt64 = 0

    init(language: SyntaxLanguage) {
        parser = TreeSitterSyntaxParser(language: language)
    }

    func highlight(
        text: String,
        range: NSRange?,
        edits: [SyntaxHighlightEditContext]?,
        baseRevision: UInt64,
        appliedRevision: UInt64,
        revision: UInt64
    ) -> TreeSitterHighlightWork? {
        guard !Task.isCancelled, revision > self.revision else { return nil }
        let mustReset = baseRevision != self.revision || edits == nil
        // A parsed revision may have been discarded before its colors reached the editor.
        let mustRecolor = mustReset || appliedRevision != self.revision
        if mustReset { parser.reset() }
        let work = parser.highlight(text: text, in: mustRecolor ? nil : range, edits: edits ?? [])
        self.revision = revision
        return work
    }
}

final class TreeSitterSyntaxParser {
    private static let sqlIdentifierContinuation = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))

    // shortcut: SQL treats bind placeholders as parse errors; extend when supporting a new placeholder form.
    private static let sqlParameterPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_$:])(?:@@?|:|\$)[A-Za-z_0-9][A-Za-z0-9_$]*(?![A-Za-z0-9_$])|(?<![A-Za-z0-9_$])\?(?![A-Za-z0-9_$])"#
    )

    private let syntax: SyntaxLanguage
    private let parser = Parser()
    private let query: Query
    private let inlineParser: Parser?
    private let inlineQuery: Query?
    private let inlineRangesQuery: Query?
    private var tree: MutableTree?
    private var inlineTree: MutableTree?
    private var textLength = 0
    private var lineStarts = [0]
    private var hadNestedSQLComments = false

    init(language syntax: SyntaxLanguage) {
        guard let definition = TreeSitterSyntaxGrammar.definition(for: syntax) else {
            preconditionFailure("Plaintext has no Tree-sitter grammar")
        }
        self.syntax = syntax
        try! parser.setLanguage(definition.language)
        query = definition.highlightsQuery

        if let inlineLanguage = definition.inlineLanguage,
           let inlineHighlightsQuery = definition.inlineHighlightsQuery,
           let inlineRangesQuery = definition.inlineRangesQuery {
            let parser = Parser()
            try! parser.setLanguage(inlineLanguage)
            inlineParser = parser
            inlineQuery = inlineHighlightsQuery
            self.inlineRangesQuery = inlineRangesQuery
        } else {
            inlineParser = nil
            inlineQuery = nil
            inlineRangesQuery = nil
        }
    }

    func reset() {
        tree = nil
        inlineTree = nil
        parser.reset()
        inlineParser?.reset()
        textLength = 0
        lineStarts = [0]
        hadNestedSQLComments = false
    }

    func highlight(
        text: String,
        in requestedRange: NSRange?,
        edits: [SyntaxHighlightEditContext] = []
    ) -> TreeSitterHighlightWork {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        guard source.length < Int(UInt32.max) / 2 else {
            reset()
            return TreeSitterHighlightWork(range: fullRange, tokens: [])
        }

        var range = (requestedRange ?? fullRange).clamped(toLength: source.length)
        let nestedComments = syntax == .sql ? SQLNestedComments.mask(in: text) : nil
        // shortcut: nested SQL comments need a full reparse; remove masking when the grammar supports nesting.
        if nestedComments != nil || hadNestedSQLComments {
            reset()
            range = fullRange
        }
        for edit in edits where tree != nil {
            guard apply(edit) else { reset(); range = fullRange; break }
        }
        if tree == nil || textLength != source.length {
            if tree != nil { range = fullRange }
            reset()
            lineStarts = [0]
            for (offset, unit) in text.utf16.enumerated() where unit == 10 {
                lineStarts.append(offset + 1)
            }
        }

        let oldTree = tree
        hadNestedSQLComments = nestedComments != nil
        tree = parse(parser, oldTree: oldTree, source: nestedComments?.source ?? source)
        textLength = source.length
        guard let tree else { return TreeSitterHighlightWork(range: fullRange, tokens: []) }
        if let oldTree {
            for change in tree.changedRanges(from: oldTree) {
                range = NSUnionRange(range, change.bytes.range).clamped(toLength: source.length)
            }
        }

        if let inlineParser, let inlineRangesQuery {
            let inlineRanges = inlineRangesQuery.execute(in: tree).flatMap { match in
                match.captures.map(\.node.tsRange).filter { $0.bytes.lowerBound < $0.bytes.upperBound }
            }
            inlineParser.includedRanges = inlineRanges
            let previousInlineTree = inlineTree
            if inlineRanges.isEmpty {
                inlineTree = nil
                inlineParser.reset()
            } else {
                inlineTree = parse(inlineParser, oldTree: previousInlineTree, source: source)
                if let inlineTree, let previousInlineTree {
                    for change in inlineTree.changedRanges(from: previousInlineTree) {
                        range = NSUnionRange(range, change.bytes.range).clamped(toLength: source.length)
                    }
                }
            }
        }

        range = source.lineRange(for: range.clamped(toLength: source.length)).clamped(toLength: source.length)
        var tokens = captures(from: query, in: tree, range: range, source: source)
        if let inlineQuery, let inlineTree {
            tokens.append(contentsOf: captures(from: inlineQuery, in: inlineTree, range: range, source: source))
        }
        tokens.append(contentsOf: (nestedComments?.ranges ?? []).map {
            TreeSitterHighlightWork.Token(range: $0, role: .comment)
        })
        tokens = tokens.filter { NSIntersectionRange($0.range, range).length > 0 }
        tokens.sort {
            if $0.range.location == $1.range.location {
                if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
                return rolePriority($0.role) < rolePriority($1.role)
            }
            return $0.range.location < $1.range.location
        }
        return TreeSitterHighlightWork(range: range, tokens: tokens)
    }

    private func parse(_ parser: Parser, oldTree: MutableTree?, source: NSString) -> MutableTree? {
        parser.parse(tree: oldTree) { byteOffset, _ in
            let location = byteOffset / 2
            let count = min(2_048, source.length - location)
            guard count > 0 else { return nil }
            var data = Data(count: count * 2)
            data.withUnsafeMutableBytes { bytes in
                source.getCharacters(
                    bytes.bindMemory(to: UInt16.self).baseAddress!,
                    range: NSRange(location: location, length: count)
                )
            }
            return data
        }
    }

    private func captures(from query: Query, in tree: MutableTree, range: NSRange, source: NSString) -> [TreeSitterHighlightWork.Token] {
        let cursor = query.execute(in: tree)
        cursor.setRange(range)
        let matches = cursor.resolve(with: Predicate.Context(string: source as String))
        return matches.flatMap { match in
            match.captures.compactMap { capture in
                var tokenRange = capture.range
                guard let captureName = capture.name, tokenRange.length > 0 else { return nil }
                if syntax == .sql, captureName == "keyword", !isWholeSQLKeyword(tokenRange, in: source) {
                    return nil
                }
                var role = TreeSitterSyntaxGrammar.role(
                    for: captureName,
                    text: source.substring(with: tokenRange.clamped(toLength: source.length)),
                    syntax: syntax
                )
                if syntax == .sql, captureName == "sqlParameter" {
                    let errorText = source.substring(with: tokenRange.clamped(toLength: source.length))
                    let errorRange = NSRange(location: 0, length: (errorText as NSString).length)
                    guard let parameter = Self.sqlParameterPattern.firstMatch(in: errorText, range: errorRange) else {
                        return nil
                    }
                    tokenRange = NSRange(
                        location: tokenRange.location + parameter.range.location,
                        length: parameter.range.length
                    )
                    role = .variable
                }
                if syntax == .sql, captureName == "variable", tokenRange.location > 0 {
                    let previousLocation = tokenRange.location - 1
                    let prefix = source.substring(with: NSRange(location: previousLocation, length: 1))
                    let repeatedColon = prefix == ":" && previousLocation > 0
                        && source.substring(with: NSRange(location: previousLocation - 1, length: 1)) == ":"
                    if [":", "$", "@"].contains(prefix), !repeatedColon {
                        let repeatedAt = prefix == "@" && previousLocation > 0
                            && source.substring(with: NSRange(location: previousLocation - 1, length: 1)) == "@"
                        let prefixLength = repeatedAt ? 2 : 1
                        tokenRange = NSRange(
                            location: tokenRange.location - prefixLength,
                            length: tokenRange.length + prefixLength
                        )
                        role = .variable
                    }
                }
                guard let role else { return nil }
                if syntax == .markdown, ["listMarker", "blockquoteMarker"].contains(captureName) {
                    let capturedText = source.substring(with: tokenRange)
                    let trimmedText = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let marker = capturedText.range(of: trimmedText) {
                        tokenRange = NSRange(
                            location: tokenRange.location + capturedText[..<marker.lowerBound].utf16.count,
                            length: trimmedText.utf16.count
                        )
                    }
                }
                return TreeSitterHighlightWork.Token(range: tokenRange, role: role)
            }
        }
    }

    private func isWholeSQLKeyword(_ range: NSRange, in source: NSString) -> Bool {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= source.length else { return false }
        return !isSQLIdentifierContinuation(at: range.location - 1, in: source)
            && !isSQLIdentifierContinuation(at: NSMaxRange(range), in: source)
    }

    private func isSQLIdentifierContinuation(at offset: Int, in source: NSString) -> Bool {
        guard offset >= 0, offset < source.length else { return false }
        let characterRange = source.rangeOfComposedCharacterSequence(at: offset)
        return source.substring(with: characterRange).unicodeScalars.contains {
            Self.sqlIdentifierContinuation.contains($0)
        }
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
        let inputEdit = InputEdit(
            startByte: range.location * 2,
            oldEndByte: NSMaxRange(range) * 2,
            newEndByte: (range.location + replacement.count) * 2,
            startPoint: start,
            oldEndPoint: end,
            newEndPoint: newEnd
        )
        tree?.edit(inputEdit)
        inlineTree?.edit(inputEdit)

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

    private func rolePriority(_ role: SyntaxColorRole) -> Int {
        switch role {
        case .variable, .plainText: 0
        case .builtin: 1
        case .string, .comment, .operator: 2
        default: 3
        }
    }
}
