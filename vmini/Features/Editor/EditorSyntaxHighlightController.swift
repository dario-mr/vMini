import AppKit

@MainActor
final class EditorSyntaxHighlightController {
    private let highlighterRegistry: HighlighterRegistry
    private let textStorageProvider: () -> NSTextStorage?
    private let syntaxThemeProvider: () -> SyntaxTheme
    private let baseFontProvider: () -> NSFont

    private var isApplyingHighlighting = false
    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingHighlight: PendingHighlight = .none
    private var pendingTextLength: Int?
    private var pendingLanguage: SyntaxLanguage = .plaintext
    private var bashMultilineTokenRanges: [NSRange]?
    private var bashCacheTextLength: Int?
    private var markdownFenceCache: MarkdownSyntaxHighlighter.FenceCache?
    private var markdownHighlightWorkTask: Task<MarkdownSyntaxHighlighter.HighlightWork?, Never>?
    private var textRevision: UInt64 = 0

    private enum PendingHighlight {
        case none
        case range(NSRange)
        case full
    }

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
        markdownHighlightWorkTask?.cancel()
        markdownHighlightWorkTask = nil
        textRevision &+= 1
        let textLength = textStorageProvider()?.length ?? 0
        if pendingLanguage != language, !isPendingHighlightEmpty {
            pendingHighlight = .full
            pendingTextLength = nil
        } else {
            pendingHighlight = pendingHighlightAdjusted(for: editContext, currentTextLength: textLength)
        }

        pendingLanguage = language
        if language != .bash {
            bashMultilineTokenRanges = nil
            bashCacheTextLength = nil
        }
        if language != .markdown {
            markdownFenceCache = nil
        }

        if let editedRange {
            let incoming = expandedHighlightRange(for: editedRange, language: language, editContext: editContext)
            pendingHighlight = mergedHighlight(pendingHighlight, with: incoming, textLength: textLength)
            if case .range = pendingHighlight {
                pendingTextLength = textLength
            }
        } else {
            pendingHighlight = .full
            pendingTextLength = nil
            if language == .markdown {
                markdownFenceCache = nil
            }
        }

        pendingRefreshTask?.cancel()
        let scheduledRevision = textRevision
        pendingRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            } else {
                await Task.yield()
            }

            guard !Task.isCancelled else { return }

            let target = self.pendingHighlight
            let targetLanguage = self.pendingLanguage
            self.pendingHighlight = .none
            self.pendingTextLength = nil
            self.pendingRefreshTask = nil
            switch target {
            case .none:
                return
            case .range(let range):
                await self.applyHighlighting(in: range, language: targetLanguage, revision: scheduledRevision)
            case .full:
                await self.applyHighlighting(in: nil, language: targetLanguage, revision: scheduledRevision)
            }
        }
    }

    private func applyHighlighting(in highlightRange: NSRange?, language: SyntaxLanguage, revision: UInt64) async {
        guard revision == textRevision, !Task.isCancelled else { return }
        guard let textStorage = textStorageProvider() else { return }

        let highlighter = highlighterRegistry.highlighter(for: language)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let targetRange = (highlightRange ?? fullRange).clamped(toLength: textStorage.length)

        guard targetRange.length > 0 else { return }

        let syntaxTheme = syntaxThemeProvider()
        let baseFont = baseFontProvider()
        var markdownLineStyles: [MarkdownSyntaxHighlighter.LineStyle]?
        if let markdownHighlighter = highlighter as? MarkdownSyntaxHighlighter {
            let snapshot = textStorage.string
            let cachedFenceCache = markdownFenceCache.flatMap { $0.textLength == textStorage.length ? $0 : nil }
            let work = Task.detached(priority: .userInitiated) { () -> MarkdownSyntaxHighlighter.HighlightWork? in
                let fenceCache: MarkdownSyntaxHighlighter.FenceCache
                if let cachedFenceCache {
                    fenceCache = cachedFenceCache
                } else {
                    guard let scannedCache = markdownHighlighter.makeFenceCache(
                        in: snapshot as NSString,
                        isCancelled: { Task.isCancelled }
                    ) else {
                        return nil
                    }
                    fenceCache = scannedCache
                }
                guard let lineStyles = markdownHighlighter.lineStylePlan(
                    in: snapshot,
                    targetRange: targetRange,
                    fences: fenceCache.blocks,
                    isCancelled: { Task.isCancelled }
                ) else {
                    return nil
                }
                return MarkdownSyntaxHighlighter.HighlightWork(fenceCache: fenceCache, lineStyles: lineStyles)
            }
            markdownHighlightWorkTask = work
            guard let result = await work.value else { return }
            guard revision == textRevision, !Task.isCancelled else { return }
            markdownHighlightWorkTask = nil
            markdownFenceCache = result.fenceCache
            markdownLineStyles = result.lineStyles
        }

        isApplyingHighlighting = true
        textStorage.beginEditing()
        textStorage.applyFont(baseFont, range: targetRange)
        textStorage.applyForegroundColor(syntaxTheme.plainText, range: targetRange)
        textStorage.applyBackgroundColor(nil, range: targetRange)
        if let markdownHighlighter = highlighter as? MarkdownSyntaxHighlighter,
           let fenceCache = markdownFenceCache,
           let markdownLineStyles {
            markdownHighlighter.highlight(
                textStorage: textStorage,
                in: targetRange,
                baseFont: baseFont,
                theme: syntaxTheme,
                registry: highlighterRegistry,
                fenceCache: fenceCache,
                lineStyles: markdownLineStyles
            )
        } else if let bashHighlighter = highlighter as? BashSyntaxHighlighter {
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
        if let markdownHighlighter = highlighter as? MarkdownSyntaxHighlighter {
            guard let editContext,
                  let markdownFenceCache,
                  let update = markdownHighlighter.updateFenceCache(markdownFenceCache, editContext: editContext, in: text) else {
                self.markdownFenceCache = nil
                return NSRange(location: 0, length: text.length)
            }
            self.markdownFenceCache = update.cache
            return update.highlightRange.clamped(toLength: text.length)
        }

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

    private var isPendingHighlightEmpty: Bool {
        if case .none = pendingHighlight { return true }
        return false
    }

    private func pendingHighlightAdjusted(
        for editContext: SyntaxHighlightEditContext?,
        currentTextLength: Int
    ) -> PendingHighlight {
        guard case .range(let range) = pendingHighlight else {
            return pendingHighlight
        }
        guard let editContext,
              let pendingTextLength,
              let adjustedRange = adjusted(range, through: editContext, currentTextLength: currentTextLength),
              pendingTextLength == currentTextLength
                - (editContext.replacementString as NSString).length
                + (editContext.replacedText as NSString).length else {
            return .full
        }
        return .range(adjustedRange)
    }

    private func adjusted(
        _ range: NSRange,
        through editContext: SyntaxHighlightEditContext,
        currentTextLength: Int
    ) -> NSRange? {
        let editRange = editContext.replacementRange
        let replacedLength = (editContext.replacedText as NSString).length
        let replacementLength = (editContext.replacementString as NSString).length
        let oldLength = currentTextLength - replacementLength + replacedLength
        guard editRange.length == replacedLength,
              editRange.location <= oldLength,
              editRange.upperBound <= oldLength else {
            return nil
        }

        let delta = replacementLength - replacedLength
        if range.upperBound <= editRange.location {
            return range.clamped(toLength: currentTextLength)
        }
        if range.location >= editRange.upperBound {
            return NSRange(location: range.location + delta, length: range.length)
                .clamped(toLength: currentTextLength)
        }

        let start = min(range.location, editRange.location)
        let end = max(
            range.upperBound > editRange.upperBound ? range.upperBound + delta : editRange.location + replacementLength,
            editRange.location + replacementLength
        )
        return NSRange(location: start, length: max(end - start, 0)).clamped(toLength: currentTextLength)
    }

    private func mergedHighlight(
        _ existing: PendingHighlight,
        with incomingRange: NSRange,
        textLength: Int
    ) -> PendingHighlight {
        let incomingRange = incomingRange.clamped(toLength: textLength)
        if incomingRange.location == 0, incomingRange.length == textLength {
            return .full
        }

        switch existing {
        case .none:
            return .range(incomingRange)
        case .range(let existingRange):
            return .range(NSUnionRange(existingRange, incomingRange))
        case .full:
            return .full
        }
    }
}
