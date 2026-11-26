import Foundation
import OSLog
import SwiftTreeSitter

struct TreeSitterHighlightWork: Sendable {
    struct Token: Sendable {
        let range: NSRange
        let role: SyntaxColorRole
    }

    let range: NSRange
    let tokens: [Token]
    var markdownHTMLBlocks: [NSRange]? = nil
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
        revision: UInt64,
        signpostID: OSSignpostID? = nil
    ) -> TreeSitterHighlightWork? {
        guard !Task.isCancelled, revision > self.revision else { return nil }
        let mustReset = baseRevision != self.revision || edits == nil
        // A parsed revision may have been discarded before its colors reached the editor.
        let mustRecolor = mustReset || appliedRevision != self.revision
        if mustReset { parser.reset() }
        let work = AppPerformanceProfiler.measure("TreeSitterParse", id: signpostID) {
            parser.highlight(text: text, in: mustRecolor ? nil : range, edits: edits ?? [])
        }
        self.revision = revision
        return work
    }
}

final class TreeSitterSyntaxParser {
    private let syntax: SyntaxLanguage
    private let parser = Parser()
    private let query: Query?
    private let markdownInlineParser: MarkdownInlineSyntaxParser?
    private var tree: MutableTree?
    private var textLength = 0
    private var lineStarts = [0]
    private var sqlTokens: [TreeSitterHighlightWork.Token]?

    init(language syntax: SyntaxLanguage) {
        self.syntax = syntax
        // SQL has no grammar: it is tokenized by SQLSyntaxLexer.
        guard let definition = TreeSitterSyntaxGrammar.definition(for: syntax) else {
            query = nil
            markdownInlineParser = nil
            return
        }
        try! parser.setLanguage(definition.language)
        query = definition.highlightsQuery

        markdownInlineParser = MarkdownInlineSyntaxParser(definition: definition)
    }

    func reset() {
        tree = nil
        parser.reset()
        markdownInlineParser?.reset()
        textLength = 0
        lineStarts = [0]
        sqlTokens = nil
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
        if syntax == .sql { return sqlHighlight(source: source, range: requestedRange == nil ? nil : range) }
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
        tree = Self.parse(parser, oldTree: oldTree, source: source)
        textLength = source.length
        guard let tree, let query else { return TreeSitterHighlightWork(range: fullRange, tokens: []) }
        if let oldTree {
            for change in tree.changedRanges(from: oldTree) {
                range = NSUnionRange(range, change.bytes.range).clamped(toLength: source.length)
            }
        }

        let inlineWork = markdownInlineParser?.highlight(in: tree, source: source, range: range)
        range = inlineWork?.range
            ?? source.lineRange(for: range.clamped(toLength: source.length)).clamped(toLength: source.length)
        var tokens = Self.captures(from: query, in: tree, range: range, source: source, syntax: syntax)
        tokens.append(contentsOf: inlineWork?.tokens ?? [])
        tokens = tokens.filter { NSIntersectionRange($0.range, range).length > 0 }
        tokens.sort {
            if $0.range.location == $1.range.location {
                if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
                return rolePriority($0.role) < rolePriority($1.role)
            }
            return $0.range.location < $1.range.location
        }
        return TreeSitterHighlightWork(range: range, tokens: tokens,
            markdownHTMLBlocks: syntax == .markdown ? MarkdownHTMLBlocks.ranges(in: tree) : nil)
    }

    static func parse(_ parser: Parser, oldTree: MutableTree?, source: NSString) -> MutableTree? {
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

    static func captures(
        from query: Query, in tree: MutableTree, range: NSRange, source: NSString, syntax: SyntaxLanguage
    ) -> [TreeSitterHighlightWork.Token] {
        let cursor = query.execute(in: tree)
        cursor.setRange(range)
        let matches = cursor.resolve(with: Predicate.Context(string: source as String))
        return matches.flatMap { match in
            match.captures.compactMap { capture in
                var tokenRange = capture.range
                guard let captureName = capture.name, tokenRange.length > 0 else { return nil }
                let role = TreeSitterSyntaxGrammar.role(
                    for: captureName,
                    text: source.substring(with: tokenRange.clamped(toLength: source.length)),
                    syntax: syntax
                )
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

    private func sqlHighlight(source: NSString, range: NSRange?) -> TreeSitterHighlightWork {
        let tokens = SQLSyntaxLexer.tokens(in: source)
        defer {
            sqlTokens = tokens
            textLength = source.length
        }
        let fullRange = NSRange(location: 0, length: source.length)
        guard let range, let previous = sqlTokens else { return TreeSitterHighlightWork(range: fullRange, tokens: tokens) }
        let dirty = SQLSyntaxLexer.dirtyRange(old: previous, new: tokens, edited: range, delta: source.length - textLength)
        let lines = source.lineRange(for: dirty.clamped(toLength: source.length))
        return TreeSitterHighlightWork(range: lines, tokens: tokens.filter { NSIntersectionRange($0.range, lines).length > 0 })
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
        markdownInlineParser?.edit(inputEdit)

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
