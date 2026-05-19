import AppKit

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    private enum Constants {
        static let lineSpacing: CGFloat = 2
    }

    var onTextChanged: (() -> Void)?
    var onFileSystemURLsDropped: (([URL]) -> Void)?
    var onJSONFormattingError: ((String, String) -> Void)? {
        didSet {
            formattingErrorPresenter.onJSONFormattingError = onJSONFormattingError
        }
    }
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
        },
        baseFontProvider: {
            EditorFontResolver.font(
                for: EditorSettings.currentFontID(),
                size: EditorSettings.currentFontSize()
            )
        }
    )
    private lazy var bracketHighlightController = EditorBracketHighlightController(
        textView: textView,
        highlightColorProvider: {
            AppColors.primaryActionBackground.withAlphaComponent(0.35)
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
    private lazy var formattingErrorPresenter = EditorFormattingErrorPresenter(
        bannerView: formattingErrorBannerView,
        scrollView: scrollView,
        textView: textView,
        windowProvider: { [weak self] in self?.view.window }
    )
    private lazy var commandController = EditorCommandController(
        textView: textView,
        viewportController: viewportController,
        syntaxLanguageProvider: { [weak self] in self?.syntaxLanguage ?? .plaintext },
        errorPresenter: formattingErrorPresenter,
        notifyCursorPositionChanged: { [weak self] in self?.notifyCursorPositionChanged() }
    )
    private var settingsObserver: EditorSettingsObserver?
    var formattingErrorMessage: String? {
        formattingErrorPresenter.message
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
        formattingErrorPresenter.onJSONFormattingError = onJSONFormattingError
        settingsObserver = EditorSettingsObserver(
            contentView: scrollView.contentView,
            applyAppearance: { [weak self] in
                self?.textViewStyler.applyAppearance()
                self?.refreshSyntaxHighlighting()
            },
            applyWordWrap: { [weak self] in
                self?.textViewStyler.applyWordWrap(EditorSettings.isWordWrapEnabled())
            },
            applyInvisibleCharacters: { [weak self] in
                self?.textViewStyler.applyInvisibleCharactersVisibility(EditorSettings.showsInvisibleCharacters())
            },
            handleScrollBoundsChange: { [weak self] in
                self?.viewportController.handleScrollBoundsChange()
                self?.formattingErrorPresenter.updateLayout()
            },
            handleThemeChange: { [weak self] in
                self?.textViewStyler.applyAppearance()
                self?.refreshSyntaxHighlighting()
                self?.viewportController.handleThemeDidChange()
            }
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
        formattingErrorPresenter.updateLayout()
    }

    func textDidChange(_ notification: Notification) {
        formattingErrorPresenter.clear()
        textViewStyler.synchronizeWordWrapLayout()
        bracketHighlightController.refresh()
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
        bracketHighlightController.refresh()
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
        commandController.toggleLineComment()
    }

    func duplicateSelectedLines() {
        commandController.duplicateSelectedLines()
    }

    func deleteCurrentLine() {
        commandController.deleteCurrentLine()
    }

    @discardableResult
    func moveSelectedLinesUp() -> Bool {
        commandController.moveSelectedLinesUp()
    }

    @discardableResult
    func moveSelectedLinesDown() -> Bool {
        commandController.moveSelectedLinesDown()
    }

    func formatJSONSelectionOrDocument() {
        commandController.formatJSONSelectionOrDocument()
    }

    func currentLineNumber() -> Int {
        commandController.currentLineNumber()
    }

    func currentCursorPosition() -> EditorCursorPosition {
        commandController.currentCursorPosition()
    }

    @discardableResult
    func goToLine(_ lineNumber: Int) -> Bool {
        commandController.goToLine(lineNumber) { [weak self] in
            self?.focusTextView()
        }
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
        bracketHighlightController.refresh()
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
        bracketHighlightController.refresh()
    }

    private func notifyCursorPositionChanged() {
        onCursorPositionChanged?()
    }

    func dismissFormattingErrorBanner() {
        formattingErrorPresenter.dismiss()
    }
}
