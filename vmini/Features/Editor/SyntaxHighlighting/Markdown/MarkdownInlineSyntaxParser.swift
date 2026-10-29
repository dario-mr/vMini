import Foundation
import SwiftTreeSitter

final class MarkdownInlineSyntaxParser {
    private let parser: Parser
    private let query: Query
    private let rangesQuery: Query
    private var trees: [MutableTree] = []

    init?(definition: TreeSitterSyntaxDefinition) {
        guard let language = definition.inlineLanguage,
              let query = definition.inlineHighlightsQuery,
              let rangesQuery = definition.inlineRangesQuery else { return nil }
        parser = Parser()
        try! parser.setLanguage(language)
        self.query = query
        self.rangesQuery = rangesQuery
    }

    func reset() {
        trees = []
        parser.reset()
    }

    func edit(_ edit: InputEdit) {
        for tree in trees { tree.edit(edit) }
    }

    func highlight(in tree: MutableTree, source: NSString, range requestedRange: NSRange) -> TreeSitterHighlightWork {
        var range = requestedRange
        // A newline edit can create a block immediately after the edited range.
        let boundaryRange = NSRange(location: range.location, length: min(range.length + 1, source.length - range.location))
        range = source.lineRange(for: boundaryRange).clamped(toLength: source.length)
        let inlineRanges = rangesQuery.execute(in: tree).flatMap { match in
            match.captures.map(\.node.tsRange).filter { $0.bytes.lowerBound < $0.bytes.upperBound }
        }
        var updatedTrees: [MutableTree] = []
        var reusedIndices: Set<Int> = []
        var firstCandidate = 0

        for inlineRange in inlineRanges {
            let blockRange = inlineRange.bytes.range
            let bestIndex = matchingTreeIndex(for: blockRange, startingAt: &firstCandidate)
            let previousTree = bestIndex.map { trees[$0] }
            if let bestIndex { reusedIndices.insert(bestIndex) }
            if let previousTree, let root = previousTree.rootNode,
               root.range == blockRange, !root.hasChanges {
                updatedTrees.append(previousTree)
                continue
            }
            // Changed node ranges alone can omit the start of a removed multiline code span.
            if let previousTree {
                for token in TreeSitterSyntaxParser.captures(
                    from: query, in: previousTree, range: range, source: source, syntax: .markdown
                ) where token.range.intersects(range) {
                    range = NSUnionRange(range, token.range.clamped(toLength: source.length))
                }
            }
            // Inline delimiters may span lines, but must never pair across Markdown blocks.
            parser.includedRanges = [inlineRange]
            guard let inlineTree = TreeSitterSyntaxParser.parse(parser, oldTree: previousTree, source: source) else { continue }
            updatedTrees.append(inlineTree)
            if let previousTree {
                for change in inlineTree.changedRanges(from: previousTree) {
                    let changedRange = NSIntersectionRange(change.bytes.range, blockRange)
                    if changedRange.length > 0 { range = NSUnionRange(range, changedRange) }
                }
            } else {
                range = NSUnionRange(range, blockRange)
            }
            for token in TreeSitterSyntaxParser.captures(
                from: query, in: inlineTree, range: range, source: source, syntax: .markdown
            ) where token.range.intersects(range) {
                range = NSUnionRange(range, token.range)
            }
        }
        for index in trees.indices where !reusedIndices.contains(index) {
            if let oldRange = trees[index].rootNode?.range {
                range = NSUnionRange(range, oldRange.clamped(toLength: source.length))
            }
        }
        trees = updatedTrees

        range = source.lineRange(for: range.clamped(toLength: source.length)).clamped(toLength: source.length)
        var tokens: [TreeSitterHighlightWork.Token] = []
        for tree in trees where tree.rootNode?.range.intersects(range) == true {
            tokens.append(contentsOf: TreeSitterSyntaxParser.captures(
                from: query, in: tree, range: range, source: source, syntax: .markdown
            ))
        }
        return TreeSitterHighlightWork(range: range, tokens: tokens)
    }

    // Reuse the largest overlapping tree when an edit splits or merges Markdown blocks.
    private func matchingTreeIndex(for blockRange: NSRange, startingAt firstCandidate: inout Int) -> Int? {
        while firstCandidate < trees.count,
              (trees[firstCandidate].rootNode?.range.upperBound ?? 0) <= blockRange.location {
            firstCandidate += 1
        }
        var candidate = firstCandidate
        var bestIndex: Int?
        var bestOverlap = 0
        while candidate < trees.count, let oldRange = trees[candidate].rootNode?.range,
              oldRange.location < blockRange.upperBound {
            let overlap = NSIntersectionRange(oldRange, blockRange).length
            if overlap > bestOverlap {
                bestIndex = candidate
                bestOverlap = overlap
            }
            candidate += 1
        }
        return bestIndex
    }
}
