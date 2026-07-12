import AppKit

@MainActor
final class EditorSyntaxHighlightController {
    private let highlighterRegistry: HighlighterRegistry
    private let textStorageProvider: () -> NSTextStorage?
    private let syntaxThemeProvider: () -> SyntaxTheme
    private let baseFontProvider: () -> NSFont

    private var isApplyingHighlighting = false
    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingHighlightRange: NSRange?
    private var pendingLanguage: SyntaxLanguage = .plaintext

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
        scheduleHighlightingRefresh(around: nil, language: language, debounceNanoseconds: 0)
    }

    func handleProcessedEditing(
        editedMask: NSTextStorageEditActions,
        editedRange: NSRange,
        language: SyntaxLanguage,
        editContext: SyntaxHighlightEditContext? = nil
    ) {
        guard editedMask.contains(.editedCharacters), !isApplyingHighlighting else {
            return
        }

        scheduleHighlightingRefresh(
            around: editedRange,
            language: language,
            editContext: editContext,
            debounceNanoseconds: 75_000_000
        )
    }

    private func scheduleHighlightingRefresh(
        around editedRange: NSRange?,
        language: SyntaxLanguage,
        editContext: SyntaxHighlightEditContext? = nil,
        debounceNanoseconds: UInt64
    ) {
        pendingLanguage = language
        pendingHighlightRange = mergedRange(
            existing: pendingHighlightRange,
            incoming: editedRange.map { expandedHighlightRange(for: $0, language: language, editContext: editContext) }
        )
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            } else {
                await Task.yield()
            }

            guard !Task.isCancelled else { return }

            let targetRange = self.pendingHighlightRange
            let targetLanguage = self.pendingLanguage
            self.pendingHighlightRange = nil
            self.pendingRefreshTask = nil
            self.applyHighlighting(in: targetRange, language: targetLanguage)
        }
    }

    private func applyHighlighting(in highlightRange: NSRange?, language: SyntaxLanguage) {
        guard let textStorage = textStorageProvider() else { return }

        let highlighter = highlighterRegistry.highlighter(for: language)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let targetRange = (highlightRange ?? fullRange).clamped(toLength: textStorage.length)

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

    private func expandedHighlightRange(
        for editedRange: NSRange,
        language: SyntaxLanguage,
        editContext: SyntaxHighlightEditContext?
    ) -> NSRange {
        guard let textStorage = textStorageProvider() else {
            return editedRange
        }

        let text = textStorage.string as NSString
        let highlighter = highlighterRegistry.highlighter(for: language)
        return highlighter.expandedHighlightRange(
            for: editedRange,
            editContext: editContext,
            in: text
        ).clamped(toLength: text.length)
    }

    private func mergedRange(existing: NSRange?, incoming: NSRange?) -> NSRange? {
        switch (existing, incoming) {
        case (_, nil):
            return nil
        case (nil, let range?):
            return range
        case (let existingRange?, let incomingRange?):
            return NSUnionRange(existingRange, incomingRange)
        }
    }
}
