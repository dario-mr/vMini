import AppKit
import OSLog

@MainActor
final class EditorSyntaxHighlightController {
    typealias MarkdownWorkProvider = (
        MarkdownSyntaxHighlighter, String, NSRange, MarkdownSyntaxHighlighter.FenceCache?, OSSignpostID?
    ) -> Task<MarkdownSyntaxHighlighter.HighlightWork?, Never>

    private let highlighterRegistry: HighlighterRegistry
    private let textStorageProvider: () -> NSTextStorage?
    private let syntaxThemeProvider: () -> SyntaxTheme
    private let baseFontProvider: () -> NSFont
    private let markdownWorkProvider: MarkdownWorkProvider

    private var isApplyingHighlighting = false
    private var pendingRefreshTask: Task<Void, Never>?
    private var pendingHighlight: PendingSyntaxHighlight = .none
    private var pendingLanguage: SyntaxLanguage = .plaintext
    private var markdownFenceCache: MarkdownSyntaxHighlighter.FenceCache?
    private var markdownHighlightWorkTask: Task<MarkdownSyntaxHighlighter.HighlightWork?, Never>?
    private var textRevision: UInt64 = 0
    private var treeSitterSession: TreeSitterSyntaxSession?
    private var treeSitterSessionLanguage: SyntaxLanguage?
    private var treeSitterPendingEdits: [SyntaxHighlightEditContext]? = []
    private var treeSitterSubmittedRevision: UInt64 = 0
    private var treeSitterAppliedRevision: UInt64 = 0

    init(
        highlighterRegistry: HighlighterRegistry,
        textStorageProvider: @escaping () -> NSTextStorage?,
        syntaxThemeProvider: @escaping () -> SyntaxTheme,
        baseFontProvider: @escaping () -> NSFont,
        markdownWorkProvider: @escaping MarkdownWorkProvider = EditorSyntaxHighlightController.makeMarkdownHighlightWork
    ) {
        self.highlighterRegistry = highlighterRegistry
        self.textStorageProvider = textStorageProvider
        self.syntaxThemeProvider = syntaxThemeProvider
        self.baseFontProvider = baseFontProvider
        self.markdownWorkProvider = markdownWorkProvider
    }

    func refresh(language: SyntaxLanguage) {
        scheduleHighlightingRefresh(around: nil, language: language)
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
            editContext: editContext
        )
    }

    private func scheduleHighlightingRefresh(
        around editedRange: NSRange?,
        language: SyntaxLanguage,
        editContext: SyntaxHighlightEditContext? = nil
    ) {
        markdownHighlightWorkTask?.cancel()
        markdownHighlightWorkTask = nil
        textRevision &+= 1
        if TreeSitterSyntaxGrammar.name(for: language) != nil {
            if treeSitterSessionLanguage != language {
                treeSitterSession = nil
                treeSitterSessionLanguage = language
                treeSitterPendingEdits = []
                treeSitterSubmittedRevision = 0
                treeSitterAppliedRevision = 0
            }
            if let editContext { treeSitterPendingEdits?.append(editContext) }
            else { treeSitterPendingEdits = nil }
        } else {
            treeSitterSession = nil
            treeSitterSessionLanguage = nil
            treeSitterPendingEdits = []
            treeSitterSubmittedRevision = 0
            treeSitterAppliedRevision = 0
        }
        let textLength = textStorageProvider()?.length ?? 0
        if pendingLanguage != language, !pendingHighlight.isEmpty {
            pendingHighlight = .full
        } else {
            pendingHighlight.adjust(for: editContext, currentTextLength: textLength)
        }

        pendingLanguage = language
        if language != .markdown {
            markdownFenceCache = nil
        }

        if let editedRange {
            let incoming = expandedHighlightRange(for: editedRange, language: language, editContext: editContext)
            pendingHighlight.merge(incoming, textLength: textLength)
        } else {
            pendingHighlight = .full
            if language == .markdown {
                markdownFenceCache = nil
            }
        }

        pendingRefreshTask?.cancel()
        let scheduledRevision = textRevision
        let signpostID = AppPerformanceProfiler.makeSignpostID()
        pendingRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Leave the text-storage editing callback before changing attributes.
            await Task.yield()

            guard scheduledRevision == self.textRevision, !Task.isCancelled else { return }

            self.applyTypingAttributes(for: editContext)

            let target = self.pendingHighlight
            let targetLanguage = self.pendingLanguage
            let highlightRange: NSRange?
            switch target {
            case .none:
                return
            case .range(let range, _):
                highlightRange = range
            case .full:
                highlightRange = nil
            }
            await AppPerformanceProfiler.measure("SyntaxHighlight", id: signpostID) {
                await self.applyHighlighting(
                    in: highlightRange, language: targetLanguage, revision: scheduledRevision, signpostID: signpostID
                )
            }
            // Keep the dirty range available for rebasing if an edit cancels in-flight work.
            guard scheduledRevision == self.textRevision, !Task.isCancelled else { return }
            self.pendingHighlight = .none
            self.pendingRefreshTask = nil
        }
    }

    private func applyHighlighting(
        in highlightRange: NSRange?, language: SyntaxLanguage, revision: UInt64, signpostID: OSSignpostID?
    ) async {
        guard revision == textRevision, !Task.isCancelled else { return }
        guard let textStorage = textStorageProvider() else { return }

        let highlighter = highlighterRegistry.highlighter(for: language)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var targetRange = (highlightRange ?? fullRange).clamped(toLength: textStorage.length)

        guard targetRange.length > 0 else { return }

        let syntaxTheme = syntaxThemeProvider()
        let baseFont = baseFontProvider()
        var treeSitterWork: TreeSitterHighlightWork?
        if TreeSitterSyntaxGrammar.name(for: language) != nil {
            let session = treeSitterSession ?? TreeSitterSyntaxSession(language: language)
            treeSitterSession = session
            treeSitterSessionLanguage = language
            let edits = treeSitterPendingEdits
            let baseRevision = treeSitterSubmittedRevision
            treeSitterPendingEdits = []
            treeSitterSubmittedRevision = revision
            guard let result = await session.highlight(
                text: textStorage.string, range: highlightRange, edits: edits,
                baseRevision: baseRevision, appliedRevision: treeSitterAppliedRevision, revision: revision,
                signpostID: signpostID
            ) else { return }
            guard revision == textRevision, !Task.isCancelled else { return }
            treeSitterWork = result
            targetRange = result.range
        }
        var markdownWork: MarkdownSyntaxHighlighter.HighlightWork?
        if let markdownHighlighter = highlighter as? MarkdownSyntaxHighlighter {
            let snapshot = textStorage.string
            let cachedFenceCache = markdownFenceCache.flatMap { $0.textLength == textStorage.length ? $0 : nil }
            let work = markdownWorkProvider(markdownHighlighter, snapshot, targetRange, cachedFenceCache, signpostID)
            markdownHighlightWorkTask = work
            guard let result = await work.value else { return }
            guard revision == textRevision, !Task.isCancelled else { return }
            markdownHighlightWorkTask = nil
            markdownFenceCache = result.fenceCache
            markdownWork = result
        }

        isApplyingHighlighting = true
        AppPerformanceProfiler.measure("SyntaxAttributeApplication", id: signpostID) {
            textStorage.beginEditing()
            textStorage.applyFont(baseFont, range: targetRange)
            textStorage.applyForegroundColor(syntaxTheme.plainText, range: targetRange)
            textStorage.applyBackgroundColor(nil, range: targetRange)
            textStorage.removeAttribute(.underlineStyle, range: targetRange)
            if let markdownHighlighter = highlighter as? MarkdownSyntaxHighlighter,
               let fenceCache = markdownFenceCache,
               let markdownWork {
                markdownHighlighter.highlight(
                    textStorage: textStorage,
                    in: targetRange,
                    baseFont: baseFont,
                    theme: syntaxTheme,
                    registry: highlighterRegistry,
                    fenceCache: fenceCache,
                    lineStyles: markdownWork.lineStyles,
                    fenceHighlights: markdownWork.fenceHighlights,
                    treeSitterWork: treeSitterWork
                )
            } else if let treeSitterWork {
                TreeSitterSyntaxHighlighter.apply(treeSitterWork, to: textStorage, theme: syntaxTheme)
            } else {
                highlighter.highlight(
                    textStorage: textStorage,
                    in: targetRange,
                    baseFont: baseFont,
                    theme: syntaxTheme,
                    registry: highlighterRegistry
                )
            }
            for link in WebLink.matches(in: textStorage.string, range: targetRange) {
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: link.range)
            }
            textStorage.endEditing()
        }
        isApplyingHighlighting = false
        if treeSitterWork != nil { treeSitterAppliedRevision = revision }
    }

    nonisolated private static func makeMarkdownHighlightWork(
        highlighter: MarkdownSyntaxHighlighter,
        snapshot: String,
        targetRange: NSRange,
        cachedFenceCache: MarkdownSyntaxHighlighter.FenceCache?,
        signpostID: OSSignpostID?
    ) -> Task<MarkdownSyntaxHighlighter.HighlightWork?, Never> {
        Task.detached(priority: .userInitiated) {
            AppPerformanceProfiler.measure("MarkdownHighlightWork", id: signpostID) {
                guard let fenceCache = cachedFenceCache ?? highlighter.makeFenceCache(
                    in: snapshot as NSString,
                    isCancelled: { Task.isCancelled }
                ), let lineStyles = highlighter.lineStylePlan(
                    in: snapshot,
                    targetRange: targetRange,
                    fences: fenceCache.blocks,
                    isCancelled: { Task.isCancelled }
                ), let fenceHighlights = MarkdownFenceHighlighter.highlights(
                    in: snapshot, targetRange: targetRange, fences: fenceCache.blocks,
                    isCancelled: { Task.isCancelled }, signpostID: signpostID
                ) else { return nil }
                return MarkdownSyntaxHighlighter.HighlightWork(
                    fenceCache: fenceCache, lineStyles: lineStyles, fenceHighlights: fenceHighlights
                )
            }
        }
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
        let insertedWhitespace = editContext.replacementString.first?.isWhitespace == true
        let insertedColor = textStorage.attribute(.foregroundColor, at: insertedRange.location, effectiveRange: nil) as? NSColor
        let keepPlainWhitespace = insertedWhitespace && insertedColor?.isEqual(syntaxThemeProvider().plainText) == true
        isApplyingHighlighting = true
        textStorage.beginEditing()
        for key: NSAttributedString.Key in [.foregroundColor, .font, .backgroundColor] {
            if key == .foregroundColor, keepPlainWhitespace { continue }
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

        return highlighter.expandedHighlightRange(
            for: editedRange,
            editContext: editContext,
            in: text
        ).clamped(toLength: text.length)
    }
}
