import Foundation
import OSLog

enum MarkdownFenceHighlighter {
    struct Highlight: Sendable {
        let offset: Int
        let work: TreeSitterHighlightWork
    }

    static func highlights(
        in source: String,
        targetRange: NSRange,
        fences: [MarkdownSyntaxHighlighter.FenceBlock],
        isCancelled: @Sendable () -> Bool = { false },
        signpostID: OSSignpostID? = nil
    ) -> [Highlight]? {
        let text = source as NSString
        var highlights: [Highlight] = []
        var index = MarkdownFenceCache.firstFenceIndex(intersectingOrAfter: targetRange.location, fences: fences)
        while index < fences.count, fences[index].openingLineRange.location < targetRange.upperBound {
            guard !isCancelled() else { return nil }
            let fence = fences[index]
            index += 1
            guard let info = fence.infoString,
                  let language = SyntaxLanguageResolver.resolveFenceInfoString(info),
                  TreeSitterSyntaxGrammar.name(for: language) != nil else { continue }
            let contentRange = fence.contentRange.clamped(toLength: text.length)
            let nestedRange = NSIntersectionRange(contentRange, targetRange)
            guard nestedRange.length > 0 else { continue }
            let relativeRange = NSRange(location: nestedRange.location - contentRange.location, length: nestedRange.length)
            let work = AppPerformanceProfiler.measure("TreeSitterParse", id: signpostID) {
                TreeSitterSyntaxParser(language: language).highlight(
                    text: text.substring(with: contentRange), in: relativeRange
                )
            }
            highlights.append(Highlight(
                offset: contentRange.location,
                work: TreeSitterHighlightWork(range: relativeRange, tokens: work.tokens)
            ))
        }
        return isCancelled() ? nil : highlights
    }
}
