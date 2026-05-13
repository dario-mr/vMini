import AppKit

@MainActor
final class EditorViewportController {
    private let textView: NSTextView
    private let scrollView: NSScrollView
    private let lineNumberRulerView: LineNumberRulerView
    private let synchronizeWordWrapLayout: () -> Void

    private var lineNumberRulerWidthConstraint: NSLayoutConstraint?
    private var hasCompletedInitialViewportReset = false

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
        lineNumberRulerView.invalidateLineNumbers()
    }

    func handleDocumentTextDidReset() {
        hasCompletedInitialViewportReset = false
        lineNumberRulerView.invalidateLineNumbers()
        resetInitialViewportIfNeeded()
    }

    func handleViewDidAppear() {
        resetInitialViewportIfNeeded()
    }

    func handleSelectionDidChange() {
        lineNumberRulerView.needsDisplay = true
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

    func resetInitialViewportIfNeeded() {
        guard !hasCompletedInitialViewportReset else {
            return
        }

        enforceInitialViewportReset(remainingPasses: 3)
    }

    private func enforceInitialViewportReset(remainingPasses: Int) {
        guard remainingPasses > 0 else {
            hasCompletedInitialViewportReset = true
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            textView.setSelectedRange(NSRange(location: 0, length: 0))

            if let textContainer = textView.textContainer,
               let layoutManager = textView.layoutManager {
                layoutManager.ensureLayout(for: textContainer)
            }

            scrollView.superview?.layoutSubtreeIfNeeded()

            let clipView = scrollView.contentView
            let targetOrigin = NSPoint(x: 0, y: 0)
            textView.setBoundsOrigin(.zero)
            clipView.scroll(to: targetOrigin)
            scrollView.reflectScrolledClipView(clipView)
            clipView.setBoundsOrigin(targetOrigin)
            scrollView.reflectScrolledClipView(clipView)
            lineNumberRulerView.needsDisplay = true

            if abs(clipView.bounds.origin.x - targetOrigin.x) < 0.5 && textView.bounds.origin == .zero {
                hasCompletedInitialViewportReset = true
            } else {
                enforceInitialViewportReset(remainingPasses: remainingPasses - 1)
            }
        }
    }
}
