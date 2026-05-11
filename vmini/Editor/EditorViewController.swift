import AppKit

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    private enum Constants {
        static let lineSpacing: CGFloat = 2
    }

    var onTextChanged: (() -> Void)?
    var onFileSystemURLsDropped: (([URL]) -> Void)?
    var onJSONFormattingError: ((String, String) -> Void)?
    var onCursorPositionChanged: (() -> Void)?

    private let scrollView = NSScrollView()
    private let formattingErrorBannerView = ErrorBannerView()
    private let textView = FileDropTextView()
    private let highlighterRegistry = HighlighterRegistry.shared
    private lazy var lineNumberRulerView = LineNumberRulerView(textView: textView)
    private var lineNumberRulerWidthConstraint: NSLayoutConstraint?
    private var hasCompletedInitialViewportReset = false
    private var isApplyingSyntaxHighlighting = false
    private var formattingErrorCharacterLocation: Int?
    var formattingErrorMessage: String? {
        formattingErrorBannerView.message
    }

    var syntaxLanguage: SyntaxLanguage = .plaintext {
        didSet {
            guard syntaxLanguage != oldValue else { return }
            refreshSyntaxHighlighting()
        }
    }

    var text: String {
        get { textView.string }
        set {
            guard textView.string != newValue else { return }
            textView.string = newValue
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            hasCompletedInitialViewportReset = false
            if isViewLoaded {
                applyParagraphStyle()
                refreshSyntaxHighlighting()
                lineNumberRulerView.invalidateLineNumbers()
                resetInitialViewportIfNeeded()
            }
            notifyCursorPositionChanged()
        }
    }

    var textStorage: NSTextStorage? {
        textView.textStorage
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        configureScrollView()
        configureTextView()
        configureLineNumberRuler()
        configureFormattingErrorBanner()

        view.addSubview(lineNumberRulerView)
        view.addSubview(scrollView)

        let lineNumberRulerWidthConstraint = lineNumberRulerView.widthAnchor.constraint(equalToConstant: lineNumberRulerView.ruleThickness)
        self.lineNumberRulerWidthConstraint = lineNumberRulerWidthConstraint
        NSLayoutConstraint.activate([
            lineNumberRulerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lineNumberRulerView.topAnchor.constraint(equalTo: view.topAnchor),
            lineNumberRulerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            lineNumberRulerWidthConstraint,

            scrollView.leadingAnchor.constraint(equalTo: lineNumberRulerView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSharedEditorAppearanceChange),
            name: EditorSettings.appearanceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSharedWordWrapChange),
            name: EditorSettings.wordWrapDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSharedInvisibleCharactersChange),
            name: EditorSettings.invisibleCharactersDidChangeNotification,
            object: nil
        )

        let contentView = scrollView.contentView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollBoundsChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focusTextView()
        resetInitialViewportIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        synchronizeWordWrapLayout()
        updateFormattingErrorBannerLayout()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func textDidChange(_ notification: Notification) {
        clearFormattingErrorBanner()
        synchronizeWordWrapLayout()
        onTextChanged?()
        notifyCursorPositionChanged()
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if editedMask.contains(.editedCharacters), !isApplyingSyntaxHighlighting {
            applySyntaxHighlighting(around: editedRange)
        }

        guard editedMask.contains(.editedCharacters) else {
            return
        }

        lineNumberRulerView.noteTextStorageDidEdit(
            textStorage,
            editedRange: editedRange,
            changeInLength: delta
        )
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        lineNumberRulerView.needsDisplay = true
        notifyCursorPositionChanged()
    }

    func increaseFontSize() {
        EditorSettings.increaseFontSize()
    }

    func decreaseFontSize() {
        EditorSettings.decreaseFontSize()
    }

    func focusTextView() {
        view.window?.makeFirstResponder(textView)
    }

    func toggleLineComment() {
        guard let textStorage = textView.textStorage else { return }
        let text = textView.string as NSString
        guard let edit = EditorTextEditing.toggleLineComment(
            in: text,
            selectedRange: textView.selectedRange(),
            syntaxLanguage: syntaxLanguage
        ) else {
            return
        }

        applyBufferEdit(edit, using: textStorage)
    }

    func duplicateSelectedLines() {
        guard let textStorage = textView.textStorage else { return }

        let text = textView.string as NSString
        let edit = EditorTextEditing.duplicateSelectedLines(in: text, selectedRange: textView.selectedRange())
        applyBufferEdit(edit, using: textStorage, scrollSelectionIntoView: true)
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
            clearFormattingErrorBanner()
        } catch {
            presentJSONFormattingError(
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
    func goToLine(_ lineNumber: Int) -> Bool {
        guard lineNumber > 0 else { return false }

        let text = textView.string as NSString
        let targetLocation = EditorTextEditing.characterLocation(forLineNumber: lineNumber, in: text)
        let selection = NSRange(location: targetLocation, length: 0)
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
        focusTextView()
        lineNumberRulerView.needsDisplay = true
        notifyCursorPositionChanged()
        return true
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
    }

    private func configureTextView() {
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textColor = AppColors.primaryText
        textView.onFileSystemURLsDropped = { [weak self] urls in
            self?.onFileSystemURLsDropped?(urls)
        }
        textView.onMoveSelectedLinesUp = { [weak self] in
            self?.moveSelectedLinesUp() ?? false
        }
        textView.onMoveSelectedLinesDown = { [weak self] in
            self?.moveSelectedLinesDown() ?? false
        }
        applyEditorFont()
        applyParagraphStyle()
        textView.backgroundColor = AppColors.editorBackground
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 12, height: 12)

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.textStorage?.delegate = self
        scrollView.documentView = textView
        applyEditorWordWrap(EditorSettings.isWordWrapEnabled())
        applyInvisibleCharactersVisibility(EditorSettings.showsInvisibleCharacters())
        applyTheme()
        refreshSyntaxHighlighting()
    }

    private func configureFormattingErrorBanner() {
        formattingErrorBannerView.onDismiss = { [weak self] in
            self?.dismissFormattingErrorBanner()
        }
        scrollView.contentView.addSubview(formattingErrorBannerView)
        formattingErrorBannerView.applyTheme()
    }

    private func configureLineNumberRuler() {
        lineNumberRulerView.onRuleThicknessChanged = { [weak self] ruleThickness in
            self?.lineNumberRulerWidthConstraint?.constant = ruleThickness
            self?.synchronizeWordWrapLayout()
        }
        lineNumberRulerView.invalidateLineNumbers()
    }

    private func applyEditorFont() {
        textView.font = EditorFontResolver.font(
            for: EditorSettings.currentFontID(),
            size: EditorSettings.currentFontSize()
        )
    }

    private func applyParagraphStyle() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = Constants.lineSpacing

        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle

        if let textStorage = textView.textStorage {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        }
    }

    private func refreshSyntaxHighlighting() {
        guard isViewLoaded else { return }
        applySyntaxHighlighting(around: nil)
    }

    private func applySyntaxHighlighting(around editedRange: NSRange?) {
        guard let textStorage = textView.textStorage else { return }

        let highlighter = highlighterRegistry.highlighter(for: syntaxLanguage)
        let text = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let targetRange: NSRange
        if let editedRange {
            targetRange = highlighter.expandedHighlightRange(for: editedRange, in: text).clamped(toLength: text.length)
        } else {
            targetRange = fullRange
        }

        guard targetRange.length > 0 else { return }

        isApplyingSyntaxHighlighting = true
        textStorage.beginEditing()
        textStorage.applyForegroundColor(currentSyntaxTheme().plainText, range: targetRange)
        textStorage.applyBackgroundColor(nil, range: targetRange)
        highlighter.highlight(
            textStorage: textStorage,
            in: targetRange,
            theme: currentSyntaxTheme(),
            registry: highlighterRegistry
        )
        textStorage.endEditing()
        isApplyingSyntaxHighlighting = false
    }

    private func currentSyntaxTheme() -> SyntaxTheme {
        ThemeManager.shared.syntaxTheme
    }

    private func notifyCursorPositionChanged() {
        onCursorPositionChanged?()
    }

    private func applyInvisibleCharactersVisibility(_ isVisible: Bool) {
        textView.layoutManager?.showsInvisibleCharacters = isVisible
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

    private func applyEditorWordWrap(_ isEnabled: Bool) {
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
        textView.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textView.string.utf16.count), actualCharacterRange: nil)
        lineNumberRulerView.invalidateLineNumbers()
    }

    private func synchronizeWordWrapLayout() {
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
        lineNumberRulerView.invalidateLineNumbers()
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

    @objc
    private func handleSharedEditorAppearanceChange() {
        applySharedEditorAppearance()
    }

    @objc
    private func handleSharedWordWrapChange() {
        applyEditorWordWrap(EditorSettings.isWordWrapEnabled())
    }

    @objc
    private func handleSharedInvisibleCharactersChange() {
        applyInvisibleCharactersVisibility(EditorSettings.showsInvisibleCharacters())
    }

    @objc
    private func handleScrollBoundsChange() {
        lineNumberRulerView.needsDisplay = true
        updateFormattingErrorBannerLayout()
    }

    @objc
    private func handleThemeDidChange() {
        applyTheme()
        refreshSyntaxHighlighting()
        lineNumberRulerView.needsDisplay = true
    }

    private func applyTheme() {
        textView.textColor = AppColors.primaryText
        textView.backgroundColor = AppColors.editorBackground
        formattingErrorBannerView.applyTheme()
    }

    private func applySharedEditorAppearance() {
        applyEditorFont()
        applyParagraphStyle()
        synchronizeWordWrapLayout()

        if isViewLoaded {
            lineNumberRulerView.invalidateLineNumbers()
        }
    }

    private func resetInitialViewportIfNeeded() {
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

            view.layoutSubtreeIfNeeded()

            let clipView = scrollView.contentView
            let targetOrigin = NSPoint(x: leftmostViewportOriginX(), y: 0)
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

    private func leftmostViewportOriginX() -> CGFloat {
        0
    }

    private func presentJSONFormattingError(forSelection: Bool, error: Error, characterOffset: Int) {
        let messageText = "Couldn’t Format JSON"
        let informativeText = forSelection
            ? "The selected text is not valid JSON.\n\n\(error.localizedDescription)"
            : "The current document is not valid JSON.\n\n\(error.localizedDescription)"

        if let onJSONFormattingError {
            onJSONFormattingError(messageText, informativeText)
            return
        }

        let absoluteCharacterLocation: Int
        if let formattingError = error as? JSONPrettifier.FormattingError {
            absoluteCharacterLocation = characterOffset + formattingError.characterIndex
        } else {
            absoluteCharacterLocation = characterOffset
        }

        showFormattingErrorBanner(
            "\(messageText): \(error.localizedDescription)",
            characterLocation: absoluteCharacterLocation
        )
    }

    private func showFormattingErrorBanner(_ message: String, characterLocation: Int) {
        formattingErrorCharacterLocation = characterLocation
        formattingErrorBannerView.message = message
        updateFormattingErrorBannerLayout()
    }

    func dismissFormattingErrorBanner() {
        clearFormattingErrorBanner()
    }

    private func clearFormattingErrorBanner() {
        guard formattingErrorBannerView.message != nil else {
            return
        }

        formattingErrorCharacterLocation = nil
        formattingErrorBannerView.message = nil
    }

    private func updateFormattingErrorBannerLayout() {
        guard
            let characterLocation = formattingErrorCharacterLocation,
            let clipView = scrollView.contentView as NSClipView?,
            let window = view.window
        else {
            return
        }

        formattingErrorBannerView.updateFrame(
            in: clipView,
            window: window,
            textView: textView,
            characterLocation: characterLocation
        )
    }
}
