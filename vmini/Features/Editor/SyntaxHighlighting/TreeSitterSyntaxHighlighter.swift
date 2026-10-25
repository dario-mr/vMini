import AppKit

@MainActor
class TreeSitterSyntaxHighlighter: SyntaxHighlighter {
    let language: SyntaxLanguage

    init(language: SyntaxLanguage) {
        self.language = language
    }

    func expandedHighlightRange(
        for editedRange: NSRange,
        editContext: SyntaxHighlightEditContext?,
        in text: NSString
    ) -> NSRange {
        text.lineRange(for: editedRange.clamped(toLength: text.length))
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        Self.apply(TreeSitterSyntaxParser(language: language).highlight(text: textStorage.string, in: range),
                   to: textStorage, theme: theme)
    }

    static func apply(_ work: TreeSitterHighlightWork, to textStorage: NSTextStorage, theme: SyntaxTheme, offset: Int = 0) {
        for token in work.tokens {
            let clipped = NSIntersectionRange(token.range, work.range)
            let range = NSRange(location: clipped.location + offset, length: clipped.length)
            textStorage.applyForegroundColor(theme.color(for: token.role), range: range)
        }
    }
}
