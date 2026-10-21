import AppKit

@MainActor
enum MarkdownAttributeStyler {
    enum Constants {
        static let headingScales: [CGFloat] = [1.5, 1.4, 1.3, 1.2, 1.1, 1.05]
        static let headingMarkerAlpha: CGFloat = 0.4
        static let headingColorStrengths: [CGFloat] = [1, 0.5, 0, 0, 0, 0]
    }

    static func applyFenceStyling(
        textStorage: NSTextStorage,
        text: NSString,
        fences: [MarkdownSyntaxHighlighter.FenceBlock],
        targetRange: NSRange,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        var index = MarkdownFenceCache.firstFenceIndex(intersectingOrAfter: targetRange.location, fences: fences)
        while index < fences.count, fences[index].openingLineRange.location < targetRange.upperBound {
            let fence = fences[index]
            index += 1
            guard fence.totalRange.intersects(targetRange) else { continue }

            if fence.contentRange.length > 0 {
                let backgroundRange = NSIntersectionRange(fence.contentRange, targetRange)
                if backgroundRange.length > 0 {
                    textStorage.applyBackgroundColor(theme.color(for: .codeBlockBackground), range: backgroundRange)
                }
            }

            if let openingRange = MarkdownFenceCache.visibleLineContentsRange(for: fence.openingLineRange, text: text),
               openingRange.intersects(targetRange) {
                textStorage.applyForegroundColor(theme.color(for: .codeFence), range: openingRange)
            }

            if let closingLineRange = fence.closingLineRange,
               let closingRange = MarkdownFenceCache.visibleLineContentsRange(for: closingLineRange, text: text),
               closingRange.intersects(targetRange) {
                textStorage.applyForegroundColor(theme.color(for: .codeFence), range: closingRange)
            }

            guard let infoString = fence.infoString,
                  !infoString.isEmpty,
                  let nestedHighlighter = registry.highlighter(forFenceInfoString: infoString),
                  nestedHighlighter.language != .markdown else {
                continue
            }

            let nestedRange = NSIntersectionRange(fence.contentRange, targetRange)
            guard nestedRange.length > 0 else {
                continue
            }

            nestedHighlighter.highlight(
                textStorage: textStorage,
                in: nestedRange,
                baseFont: baseFont,
                theme: theme,
                registry: registry
            )
        }
    }

    static func applyLineStyles(
        _ styles: [MarkdownSyntaxHighlighter.LineStyle],
        textStorage: NSTextStorage,
        baseFont: NSFont,
        theme: SyntaxTheme
    ) {
        let headingFont = EditorFontResolver.boldVariant(of: baseFont)
        for style in styles {
            switch style.kind {
            case .color(.headingMarker):
                textStorage.applyForegroundColor(theme.headingMarker.withAlphaComponent(Constants.headingMarkerAlpha), range: style.range)
            case .color(let role):
                textStorage.applyForegroundColor(theme.color(for: role), range: style.range)
            case .headingText(let level):
                textStorage.applyForegroundColor(Self.headingTextColor(for: level, theme: theme), range: style.range)
            case .headingFont(let level):
                let font = NSFontManager.shared.convert(headingFont, toSize: baseFont.pointSize * Constants.headingScales[level - 1])
                textStorage.applyFont(font, range: style.range)
            }
        }
    }

    private static func headingTextColor(
        for level: Int,
        theme: SyntaxTheme
    ) -> NSColor {
        let strength = Constants.headingColorStrengths[level - 1]
        return theme.headingText.blended(withFraction: strength, of: theme.headingMarker) ?? theme.headingText
    }

}
