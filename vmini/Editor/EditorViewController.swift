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
    private lazy var lineNumberRulerView = LineNumberRulerView(textView: textView)
    private lazy var textViewStyler = EditorTextViewStyler(
        textView: textView,
        scrollView: scrollView,
        lineSpacing: Constants.lineSpacing,
        invalidateLineNumbers: { [weak self] in
            self?.lineNumberRulerView.invalidateLineNumbers()
        }
    )
    private lazy var syntaxHighlightController = EditorSyntaxHighlightController(
        highlighterRegistry: .shared,
        textStorageProvider: { [weak self] in
            self?.textView.textStorage
        },
        syntaxThemeProvider: {
            ThemeManager.shared.syntaxTheme
        }
    )
    private lazy var viewportController = EditorViewportController(
        textView: textView,
        scrollView: scrollView,
        lineNumberRulerView: lineNumberRulerView,
        synchronizeWordWrapLayout: { [weak self] in
            self?.textViewStyler.synchronizeWordWrapLayout()
        }
    )
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
            if isViewLoaded {
                textViewStyler.applyParagraphStyle()
                refreshSyntaxHighlighting()
                viewportController.handleDocumentTextDidReset()
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
        viewportController.attachLineNumberRulerWidthConstraint(lineNumberRulerWidthConstraint)
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
        viewportController.handleViewDidAppear()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        textViewStyler.synchronizeWordWrapLayout()
        updateFormattingErrorBannerLayout()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func textDidChange(_ notification: Notification) {
        clearFormattingErrorBanner()
        textViewStyler.synchronizeWordWrapLayout()
        onTextChanged?()
        notifyCursorPositionChanged()
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        syntaxHighlightController.handleProcessedEditing(
            editedMask: editedMask,
            editedRange: editedRange,
            language: syntaxLanguage
        )

        guard editedMask.contains(.editedCharacters) else {
            return
        }

        viewportController.handleTextStorageDidEdit(
            textStorage,
            editedRange: editedRange,
            changeInLength: delta
        )
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        viewportController.handleSelectionDidChange()
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
        viewportController.handleCaretNavigation()
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
        textView.delegate = self
        textView.onFileSystemURLsDropped = { [weak self] urls in
            self?.onFileSystemURLsDropped?(urls)
        }
        textView.onMoveSelectedLinesUp = { [weak self] in
            self?.moveSelectedLinesUp() ?? false
        }
        textView.onMoveSelectedLinesDown = { [weak self] in
            self?.moveSelectedLinesDown() ?? false
        }

        textView.textStorage?.delegate = self
        scrollView.documentView = textView
        textViewStyler.configureTextView()
        formattingErrorBannerView.applyTheme()
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
        viewportController.configureLineNumberRuler()
    }

    private func refreshSyntaxHighlighting() {
        guard isViewLoaded else { return }
        syntaxHighlightController.refresh(language: syntaxLanguage)
    }

    private func notifyCursorPositionChanged() {
        onCursorPositionChanged?()
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

    @objc
    private func handleSharedEditorAppearanceChange() {
        textViewStyler.applyAppearance()
        refreshSyntaxHighlighting()
    }

    @objc
    private func handleSharedWordWrapChange() {
        textViewStyler.applyWordWrap(EditorSettings.isWordWrapEnabled())
    }

    @objc
    private func handleSharedInvisibleCharactersChange() {
        textViewStyler.applyInvisibleCharactersVisibility(EditorSettings.showsInvisibleCharacters())
    }

    @objc
    private func handleScrollBoundsChange() {
        viewportController.handleScrollBoundsChange()
        updateFormattingErrorBannerLayout()
    }

    @objc
    private func handleThemeDidChange() {
        textViewStyler.applyAppearance()
        refreshSyntaxHighlighting()
        viewportController.handleThemeDidChange()
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
