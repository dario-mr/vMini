import AppKit

@MainActor
final class MarkdownSyntaxHighlighter: SyntaxHighlighter {
    struct FenceBlock: Equatable, Sendable {
        let openingLineRange: NSRange
        let contentRange: NSRange
        let closingLineRange: NSRange?
        let infoString: String?

        var totalRange: NSRange {
            let end = closingLineRange?.upperBound ?? contentRange.upperBound
            return NSRange(location: openingLineRange.location, length: max(end - openingLineRange.location, 0))
        }
    }

    struct FenceCache: Sendable {
        let textLength: Int
        let blocks: [FenceBlock]
    }

    struct FenceCacheUpdate {
        let cache: FenceCache
        let highlightRange: NSRange
        let rescannedLineCount: Int
    }

    struct HighlightWork: Sendable {
        let fenceCache: FenceCache
        let lineStyles: [LineStyle]
    }

    struct LineStyle: Sendable {
        enum Kind: Sendable {
            case color(SyntaxColorRole)
            case headingText(level: Int)
            case boldFont
        }

        let kind: Kind
        let range: NSRange
    }

    let language: SyntaxLanguage = .markdown

    func expandedHighlightRange(
        for editedRange: NSRange,
        editContext: SyntaxHighlightEditContext?,
        in text: NSString
    ) -> NSRange {
        let fullRange = NSRange(location: 0, length: text.length)

        guard let editContext else {
            return fullRange
        }

        if MarkdownFenceCache.isFenceSensitiveEdit(editedRange: editedRange, editContext: editContext, in: text) {
            return fullRange
        }

        return MarkdownFenceCache.surroundingLineRange(around: editedRange, in: text)
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        let text = textStorage.string as NSString
        let targetRange = (range ?? NSRange(location: 0, length: text.length)).clamped(toLength: text.length)
        guard text.length > 0, targetRange.length > 0 else {
            return
        }

        highlight(
            textStorage: textStorage,
            in: targetRange,
            baseFont: baseFont,
            theme: theme,
            registry: registry,
            fenceCache: makeFenceCache(in: text)
        )
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry,
        fenceCache: FenceCache
    ) {
        let text = textStorage.string as NSString
        let targetRange = range.clamped(toLength: text.length)
        guard text.length > 0, targetRange.length > 0 else { return }

        highlight(
            textStorage: textStorage,
            in: targetRange,
            baseFont: baseFont,
            theme: theme,
            registry: registry,
            fenceCache: fenceCache,
            lineStyles: lineStylePlan(in: textStorage.string, targetRange: targetRange, fences: fenceCache.blocks)
        )
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry,
        fenceCache: FenceCache,
        lineStyles: [LineStyle]
    ) {
        let text = textStorage.string as NSString
        let targetRange = range.clamped(toLength: text.length)
        guard text.length > 0, targetRange.length > 0 else { return }

        MarkdownAttributeStyler.applyFenceStyling(
            textStorage: textStorage,
            text: text,
            fences: fenceCache.blocks,
            targetRange: targetRange,
            baseFont: baseFont,
            theme: theme,
            registry: registry
        )
        MarkdownAttributeStyler.applyLineStyles(lineStyles, textStorage: textStorage, baseFont: baseFont, theme: theme)
    }

    nonisolated func makeFenceCache(in text: NSString) -> FenceCache {
        MarkdownFenceCache.makeFenceCache(in: text)
    }

    nonisolated func makeFenceCache(in text: NSString, isCancelled: @Sendable () -> Bool) -> FenceCache? {
        MarkdownFenceCache.makeFenceCache(in: text, isCancelled: isCancelled)
    }

    func updateFenceCache(
        _ cache: FenceCache,
        editContext: SyntaxHighlightEditContext,
        in text: NSString
    ) -> FenceCacheUpdate? {
        MarkdownFenceCache.updateFenceCache(cache, editContext: editContext, in: text)
    }

    nonisolated func lineStylePlan(in source: String, targetRange: NSRange, fences: [FenceBlock]) -> [LineStyle] {
        MarkdownLineStylePlanner.lineStylePlan(in: source, targetRange: targetRange, fences: fences)
    }

    nonisolated func lineStylePlan(
        in source: String,
        targetRange: NSRange,
        fences: [FenceBlock],
        isCancelled: @Sendable () -> Bool
    ) -> [LineStyle]? {
        MarkdownLineStylePlanner.lineStylePlan(
            in: source,
            targetRange: targetRange,
            fences: fences,
            isCancelled: isCancelled
        )
    }

}
