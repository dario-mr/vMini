import AppKit

@MainActor
final class EditorViewportController {
    private let textView: NSTextView
    private let scrollView: NSScrollView
    private let lineNumberRulerView: LineNumberRulerView
    private let synchronizeWordWrapLayout: () -> Void

    private var lineNumberRulerWidthConstraint: NSLayoutConstraint?
    private var hasCompletedInitialViewportReset = false
    private var initialViewportResetSelection: NSRange?

    init(
        textView: NSTextView,
        scrollView: NSScrollView,
        lineNumberRulerView: LineNumberRulerView,
        synchronizeWordWrapLayout: @escaping () -> Void
    ) {
        self.textView = textView
        self.scrollView = scrollView
        self.lineNumberRulerView = lineNumberRulerView
        self.synchronizeWordWrapLayout = synchronizeWordWrapLayout
    }

    func attachLineNumberRulerWidthConstraint(_ constraint: NSLayoutConstraint) {
        lineNumberRulerWidthConstraint = constraint
    }

    func configureLineNumberRuler() {
        lineNumberRulerView.onRuleThicknessChanged = { [weak self] ruleThickness in
            self?.lineNumberRulerWidthConstraint?.constant = ruleThickness
            self?.synchronizeWordWrapLayout()
        }
        lineNumberRulerView.resetLineCache()
    }

    func handleDocumentTextDidReset() {
        hasCompletedInitialViewportReset = false
        initialViewportResetSelection = nil
        lineNumberRulerView.resetLineCache()
        resetInitialViewportIfNeeded()
    }

    func handleViewDidAppear() {
        resetInitialViewportIfNeeded()
    }

    func handleSelectionDidChange() {
        if let initialViewportResetSelection,
           textView.selectedRange() != initialViewportResetSelection {
            hasCompletedInitialViewportReset = true
            self.initialViewportResetSelection = nil
        }
        lineNumberRulerView.handleSelectionDidChange()
    }

    func handleTextStorageDidEdit(
        _ textStorage: NSTextStorage,
        editedRange: NSRange,
        changeInLength delta: Int
    ) {
        lineNumberRulerView.noteTextStorageDidEdit(
            textStorage,
            editedRange: editedRange,
            changeInLength: delta
        )
    }

    func handleScrollBoundsChange() {
        lineNumberRulerView.needsDisplay = true
    }

    func handleThemeDidChange() {
        lineNumberRulerView.needsDisplay = true
    }

    func handleCaretNavigation() {
        lineNumberRulerView.needsDisplay = true
    }

    func currentCursorPosition() -> EditorCursorPosition {
        lineNumberRulerView.currentCursorPosition()
    }

    func resetInitialViewportIfNeeded() {
        guard !hasCompletedInitialViewportReset else {
            return
        }

        guard initialViewportResetSelection == nil else { return }

        let selection = textView.selectedRange()
        initialViewportResetSelection = selection
        enforceInitialViewportReset(expectedSelection: selection)
    }

    private func enforceInitialViewportReset(expectedSelection: NSRange) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !hasCompletedInitialViewportReset,
                  initialViewportResetSelection == expectedSelection
            else { return }

            guard textView.selectedRange() == expectedSelection else {
                hasCompletedInitialViewportReset = true
                initialViewportResetSelection = nil
                return
            }

            let interval = AppPerformanceProfiler.beginInterval("InitialViewportLayout")
            defer { AppPerformanceProfiler.endInterval("InitialViewportLayout", interval) }

            let initialSelection = NSRange(location: 0, length: 0)
            initialViewportResetSelection = initialSelection
            textView.setSelectedRange(initialSelection)

            if let textContainer = textView.textContainer,
               let layoutManager = textView.layoutManager {
                layoutManager.ensureLayout(
                    forBoundingRect: NSRect(origin: .zero, size: textView.visibleRect.size),
                    in: textContainer
                )
            }

            scrollView.superview?.layoutSubtreeIfNeeded()

            textView.scrollRangeToVisible(initialSelection)
            lineNumberRulerView.needsDisplay = true
            hasCompletedInitialViewportReset = true
            initialViewportResetSelection = nil
        }
    }
}
