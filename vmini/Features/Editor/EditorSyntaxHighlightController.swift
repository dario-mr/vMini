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
    private var bashMultilineTokenRanges: [NSRange]?
    private var bashCacheTextLength: Int?

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

        applyTypingAttributes(for: editContext)
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
        if language != .bash {
            bashMultilineTokenRanges = nil
            bashCacheTextLength = nil
        }
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
        if let bashHighlighter = highlighter as? BashSyntaxHighlighter {
            bashHighlighter.highlight(
                textStorage: textStorage,
                in: targetRange,
                baseFont: baseFont,
                theme: syntaxTheme,
                registry: highlighterRegistry,
                onFullTextScan: { [weak self] ranges in
                    self?.bashMultilineTokenRanges = ranges
                    self?.bashCacheTextLength = textStorage.length
                }
            )
        } else {
            highlighter.highlight(
                textStorage: textStorage,
                in: targetRange,
                baseFont: baseFont,
                theme: syntaxTheme,
                registry: highlighterRegistry
            )
        }
        textStorage.endEditing()
        isApplyingHighlighting = false
    }

    private func applyTypingAttributes(for editContext: SyntaxHighlightEditContext?) {
        guard let editContext,
              editContext.replacedText.isEmpty,
              editContext.replacementString.count == 1,
              let textStorage = textStorageProvider() else {
            return
        }

        let insertedRange = NSRange(
            location: editContext.replacementRange.location,
            length: (editContext.replacementString as NSString).length
        ).clamped(toLength: textStorage.length)
        guard insertedRange.length > 0 else {
            return
        }

        let adjacentLocation: Int
        if insertedRange.location > 0 {
            adjacentLocation = insertedRange.location - 1
        } else if insertedRange.upperBound < textStorage.length {
            adjacentLocation = insertedRange.upperBound
        } else {
            return
        }

        let attributes = textStorage.attributes(at: adjacentLocation, effectiveRange: nil)
        isApplyingHighlighting = true
        textStorage.beginEditing()
        for key: NSAttributedString.Key in [.foregroundColor, .font, .backgroundColor] {
            if let value = attributes[key] {
                textStorage.addAttribute(key, value: value, range: insertedRange)
            } else {
                textStorage.removeAttribute(key, range: insertedRange)
            }
        }
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
        if let bashHighlighter = highlighter as? BashSyntaxHighlighter {
            if let editContext,
               let cachedRanges = bashMultilineTokenRanges,
               let cachedTextLength = bashCacheTextLength,
               let updatedRanges = bashHighlighter.updatedMultilineTokenRanges(
                   cachedRanges,
                   cachedTextLength: cachedTextLength,
                   editContext: editContext,
                   in: text
                ) {
                bashMultilineTokenRanges = updatedRanges
            } else {
                bashMultilineTokenRanges = bashHighlighter.multilineTokenRanges(in: text as String)
            }
            bashCacheTextLength = text.length
            return bashHighlighter.expandedHighlightRange(
                for: editedRange,
                cachedMultilineTokenRanges: bashMultilineTokenRanges ?? [],
                in: text
            ).clamped(toLength: text.length)
        }

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
