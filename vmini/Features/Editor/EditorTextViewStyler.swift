import AppKit

@MainActor
final class EditorTextViewStyler {
    private enum Constants {
        static let textInsetWidth: CGFloat = 0
        static let textInsetHeight: CGFloat = 2
    }

    private let textView: NSTextView
    private let scrollView: NSScrollView
    private let lineSpacing: CGFloat
    private let invalidateLineNumbers: () -> Void

    init(
        textView: NSTextView,
        scrollView: NSScrollView,
        lineSpacing: CGFloat,
        invalidateLineNumbers: @escaping () -> Void
    ) {
        self.textView = textView
        self.scrollView = scrollView
        self.lineSpacing = lineSpacing
        self.invalidateLineNumbers = invalidateLineNumbers
    }

    func configureTextView() {
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(
            width: Constants.textInsetWidth,
            height: Constants.textInsetHeight
        )

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        applyAppearance()
        applyWordWrap(EditorSettings.isWordWrapEnabled())
        applyInvisibleCharactersVisibility(EditorSettings.showsInvisibleCharacters())
    }

    func applyAppearance() {
        applyEditorFont()
        applyParagraphStyle()
        textView.textColor = AppColors.primaryText
        textView.backgroundColor = AppColors.editorBackground
        synchronizeWordWrapLayout()
        invalidateLineNumbers()
    }

    func applyParagraphStyle() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle

        if let textStorage = textView.textStorage {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        }
    }

    func applyWordWrap(_ isEnabled: Bool) {
        scrollView.hasHorizontalScroller = !isEnabled
        textView.isHorizontallyResizable = !isEnabled
        textView.autoresizingMask = [.width]

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = isEnabled
            textContainer.containerSize = NSSize(
                width: isEnabled ? wrappedContainerWidth() : CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        synchronizeWordWrapLayout()
        textView.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: textView.string.utf16.count),
            actualCharacterRange: nil
        )
        invalidateLineNumbers()
    }

    func applyInvisibleCharactersVisibility(_ isVisible: Bool) {
        textView.layoutManager?.showsInvisibleCharacters = isVisible
    }

    func synchronizeWordWrapLayout() {
        guard EditorSettings.isWordWrapEnabled() else {
            return
        }

        let viewportWidth = wrappedViewportWidth()
        let containerWidth = wrappedContainerWidth()
        let currentContainerWidth = textView.textContainer?.containerSize.width ?? 0
        guard abs(textView.frame.size.width - viewportWidth) > 0.5 || abs(currentContainerWidth - containerWidth) > 0.5 else {
            return
        }

        textView.frame.size.width = viewportWidth
        textView.textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        invalidateLineNumbers()
    }

    private func applyEditorFont() {
        textView.font = EditorFontResolver.font(
            for: EditorSettings.currentFontID(),
            size: EditorSettings.currentFontSize()
        )
    }

    private func wrappedViewportWidth() -> CGFloat {
        max(scrollView.contentSize.width, 1)
    }

    private func wrappedContainerWidth() -> CGFloat {
        let horizontalInsets = (textView.textContainerInset.width * 2) + horizontalLineFragmentPadding()
        return max(wrappedViewportWidth() - horizontalInsets, 1)
    }

    private func horizontalLineFragmentPadding() -> CGFloat {
        guard let textContainer = textView.textContainer else {
            return 0
        }

        return textContainer.lineFragmentPadding * 2
    }
}
