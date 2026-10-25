import AppKit

@MainActor
final class JavaSyntaxHighlighter: SyntaxHighlighter {
    let language: SyntaxLanguage = .java

    func expandedHighlightRange(
        for editedRange: NSRange,
        editContext: SyntaxHighlightEditContext?,
        in text: NSString
    ) -> NSRange {
        guard editContext != nil else { return NSRange(location: 0, length: text.length) }
        return text.lineRange(for: editedRange.clamped(toLength: text.length))
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        let work = JavaSyntaxParser().highlight(text: textStorage.string, in: range)
        apply(work, to: textStorage, theme: theme)
    }

    func apply(_ work: JavaHighlightWork, to textStorage: NSTextStorage, theme: SyntaxTheme) {
        for token in work.tokens {
            textStorage.applyForegroundColor(theme.color(for: token.role), range: token.range)
        }
    }
}
