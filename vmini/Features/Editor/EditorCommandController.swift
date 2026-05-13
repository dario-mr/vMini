import AppKit

@MainActor
final class EditorCommandController {
    private let textView: FileDropTextView
    private let viewportController: EditorViewportController
    private let syntaxLanguageProvider: () -> SyntaxLanguage
    private let errorPresenter: EditorFormattingErrorPresenter
    private let notifyCursorPositionChanged: () -> Void

    init(
        textView: FileDropTextView,
        viewportController: EditorViewportController,
        syntaxLanguageProvider: @escaping () -> SyntaxLanguage,
        errorPresenter: EditorFormattingErrorPresenter,
        notifyCursorPositionChanged: @escaping () -> Void
    ) {
        self.textView = textView
        self.viewportController = viewportController
        self.syntaxLanguageProvider = syntaxLanguageProvider
        self.errorPresenter = errorPresenter
        self.notifyCursorPositionChanged = notifyCursorPositionChanged
    }

    func toggleLineComment() {
        guard let textStorage = textView.textStorage else { return }
        let text = textView.string as NSString
        guard let edit = EditorTextEditing.toggleLineComment(
            in: text,
            selectedRange: textView.selectedRange(),
            syntaxLanguage: syntaxLanguageProvider()
        ) else {
            return
        }

        _ = applyBufferEdit(edit, using: textStorage)
    }

    func duplicateSelectedLines() {
        guard let textStorage = textView.textStorage else { return }

        let text = textView.string as NSString
        let edit = EditorTextEditing.duplicateSelectedLines(in: text, selectedRange: textView.selectedRange())
        _ = applyBufferEdit(edit, using: textStorage, scrollSelectionIntoView: true)
    }

    func deleteCurrentLine() {
        guard let textStorage = textView.textStorage else { return }

        let text = textView.string as NSString
        let edit = EditorTextEditing.deleteCurrentLine(in: text, selectedRange: textView.selectedRange())
        _ = applyBufferEdit(edit, using: textStorage, scrollSelectionIntoView: true)
    }

    @discardableResult
    func moveSelectedLinesUp() -> Bool {
        moveSelectedLines(direction: .up)
    }

    @discardableResult
    func moveSelectedLinesDown() -> Bool {
        moveSelectedLines(direction: .down)
    }

    func formatJSONSelectionOrDocument() {
        guard let textStorage = textView.textStorage else { return }

        let fullText = textView.string as NSString
        let originalSelection = textView.selectedRange()
        let targetRange = originalSelection.length > 0
            ? originalSelection.clamped(toLength: fullText.length)
            : NSRange(location: 0, length: fullText.length)
        let candidate = fullText.substring(with: targetRange)

        let formatted: String
        do {
            formatted = try JSONPrettifier.prettify(candidate)
            errorPresenter.clear()
        } catch {
            errorPresenter.presentJSONFormattingError(
                forSelection: originalSelection.length > 0,
                error: error,
                characterOffset: targetRange.location
            )
            return
        }

        guard textView.shouldChangeText(in: targetRange, replacementString: formatted) else {
            return
        }

        let formattedLength = (formatted as NSString).length
        let newSelection: NSRange
        if originalSelection.length > 0 {
            newSelection = NSRange(location: targetRange.location, length: formattedLength)
        } else {
            let caretLocation = min(originalSelection.location, formattedLength)
            newSelection = NSRange(location: caretLocation, length: 0)
        }

        textStorage.replaceCharacters(in: targetRange, with: formatted)
        textView.didChangeText()
        textView.setSelectedRange(newSelection)
        textView.scrollRangeToVisible(newSelection)
        notifyCursorPositionChanged()
    }

    func currentLineNumber() -> Int {
        currentCursorPosition().line
    }

    func currentCursorPosition() -> EditorCursorPosition {
        let text = textView.string as NSString
        return EditorTextEditing.currentCursorPosition(in: text, selectedRange: textView.selectedRange())
    }

    @discardableResult
    func goToLine(_ lineNumber: Int, focusEditor: () -> Void) -> Bool {
        guard lineNumber > 0 else { return false }

        let text = textView.string as NSString
        let targetLocation = EditorTextEditing.characterLocation(forLineNumber: lineNumber, in: text)
        let selection = NSRange(location: targetLocation, length: 0)
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
        focusEditor()
        viewportController.handleCaretNavigation()
        notifyCursorPositionChanged()
        return true
    }

    @discardableResult
    private func applyBufferEdit(
        _ edit: EditorTextEdit,
        using textStorage: NSTextStorage,
        scrollSelectionIntoView: Bool = false
    ) -> Bool {
        guard textView.shouldChangeText(in: edit.replacementRange, replacementString: edit.replacementText) else {
            return false
        }

        textStorage.replaceCharacters(in: edit.replacementRange, with: edit.replacementText)
        textView.didChangeText()
        textView.setSelectedRange(edit.selectedRange)
        if scrollSelectionIntoView {
            textView.scrollRangeToVisible(edit.selectedRange)
        }
        notifyCursorPositionChanged()
        return true
    }

    private func moveSelectedLines(direction: EditorLineMoveDirection) -> Bool {
        guard let textStorage = textView.textStorage else { return false }

        let text = textView.string as NSString
        guard let edit = EditorTextEditing.moveSelectedLines(
            in: text,
            selectedRange: textView.selectedRange(),
            direction: direction
        ) else {
            return false
        }

        return applyBufferEdit(edit, using: textStorage, scrollSelectionIntoView: true)
    }
}
