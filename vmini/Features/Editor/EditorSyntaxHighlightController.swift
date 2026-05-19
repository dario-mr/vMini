import AppKit

@MainActor
final class EditorSyntaxHighlightController {
    private let highlighterRegistry: HighlighterRegistry
    private let textStorageProvider: () -> NSTextStorage?
    private let syntaxThemeProvider: () -> SyntaxTheme
    private let baseFontProvider: () -> NSFont

    private var isApplyingHighlighting = false

    init(
        highlighterRegistry: HighlighterRegistry,
        textStorageProvider: @escaping () -> NSTextStorage?,
        syntaxThemeProvider: @escaping () -> SyntaxTheme,
        baseFontProvider: @escaping () -> NSFont
    ) {
        self.highlighterRegistry = highlighterRegistry
        self.textStorageProvider = textStorageProvider
        self.syntaxThemeProvider = syntaxThemeProvider
        self.baseFontProvider = baseFontProvider
    }

    func refresh(language: SyntaxLanguage) {
        applyHighlighting(around: nil, language: language)
    }

    func handleProcessedEditing(
        editedMask: NSTextStorageEditActions,
        editedRange: NSRange,
        language: SyntaxLanguage
    ) {
        guard editedMask.contains(.editedCharacters), !isApplyingHighlighting else {
            return
        }

        applyHighlighting(around: editedRange, language: language)
    }

    private func applyHighlighting(around editedRange: NSRange?, language: SyntaxLanguage) {
        guard let textStorage = textStorageProvider() else { return }

        let highlighter = highlighterRegistry.highlighter(for: language)
        let text = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let targetRange: NSRange
        if let editedRange {
            targetRange = highlighter.expandedHighlightRange(for: editedRange, in: text).clamped(toLength: text.length)
        } else {
            targetRange = fullRange
        }

        guard targetRange.length > 0 else { return }

        let syntaxTheme = syntaxThemeProvider()
        let baseFont = baseFontProvider()
        isApplyingHighlighting = true
        textStorage.beginEditing()
        textStorage.applyFont(baseFont, range: targetRange)
        textStorage.applyForegroundColor(syntaxTheme.plainText, range: targetRange)
        textStorage.applyBackgroundColor(nil, range: targetRange)
        highlighter.highlight(
            textStorage: textStorage,
            in: targetRange,
            baseFont: baseFont,
            theme: syntaxTheme,
            registry: highlighterRegistry
        )
        textStorage.endEditing()
        isApplyingHighlighting = false
    }
}
