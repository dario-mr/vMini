import AppKit

@MainActor
final class PlainTextSyntaxHighlighter: SyntaxHighlighter {
    let language: SyntaxLanguage = .plaintext

    func expandedHighlightRange(for editedRange: NSRange, in text: NSString) -> NSRange {
        text.lineRange(for: editedRange.clamped(toLength: text.length))
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
    }
}
