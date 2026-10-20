import AppKit

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    private enum Constants {
        static let lineSpacing: CGFloat = 2
    }

    var onTextChanged: (() -> Void)?
    var onFileSystemURLsDropped: (([URL]) -> Void)?
    var documentURLProvider: (() -> URL?)?
    var onOpenMarkdownURL: (URL) -> Void = { url in
        if url.isFileURL {
            WorkspaceDocumentCoordinator.shared.open(urls: [url], activate: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    var onJSONFormattingError: ((String, String) -> Void)? {
        didSet {
            formattingErrorPresenter.onJSONFormattingError = onJSONFormattingError
        }
    }
    var onCursorPositionChanged: (() -> Void)?
    var onNavigationCheckpoint: ((NSRange, NSRange) -> Void)?

    private let scrollView = NSScrollView()
    private let formattingErrorBannerView = ErrorBannerView()
    private let textView = FileDropTextView()
    private(set) lazy var searchController = EditorSearchController(textView: textView)
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
    private lazy var selectionOccurrenceController = EditorSelectionOccurrenceController(
        textView: textView,
        highlightColorProvider: {
            AppColors.primaryActionBackground.withAlphaComponent(0.6)
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
    private var pendingSyntaxHighlightEditContext: SyntaxHighlightEditContext?
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

    func markChangesSaved() {
        lineNumberRulerView.markChangesSaved()
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        configureScrollView()
        configureTextView()
        configureLineNumberRuler()
        configureFormattingErrorBanner()

        let searchPanel = searchController.panel
        searchController.onVisibilityChanged = { [weak self] isVisible in
            self?.selectionOccurrenceController.isEnabled = !isVisible
            self?.bracketHighlightController.isEnabled = !isVisible
        }
        view.addSubview(searchPanel)
        view.addSubview(lineNumberRulerView)
        view.addSubview(scrollView)

        let lineNumberRulerWidthConstraint = lineNumberRulerView.widthAnchor.constraint(equalToConstant: lineNumberRulerView.ruleThickness)
        viewportController.attachLineNumberRulerWidthConstraint(lineNumberRulerWidthConstraint)
        NSLayoutConstraint.activate([
            searchPanel.topAnchor.constraint(equalTo: view.topAnchor),
            searchPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lineNumberRulerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lineNumberRulerView.topAnchor.constraint(equalTo: searchPanel.bottomAnchor),
            lineNumberRulerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            lineNumberRulerWidthConstraint,

            scrollView.leadingAnchor.constraint(equalTo: lineNumberRulerView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: searchPanel.bottomAnchor),
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
        selectionOccurrenceController.refresh()
        bracketHighlightController.refresh()
        searchController.refresh()
        onTextChanged?()
        notifyCursorPositionChanged()
    }

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        let text = textView.string as NSString
        let replacementRange = affectedCharRange.clamped(toLength: text.length)
        pendingSyntaxHighlightEditContext = SyntaxHighlightEditContext(
            replacementRange: replacementRange,
            replacementString: replacementString ?? "",
            replacedText: text.substring(with: replacementRange)
        )
        return true
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
            language: syntaxLanguage,
            editContext: pendingSyntaxHighlightEditContext
        )

        guard editedMask.contains(.editedCharacters) else {
            return
        }

        pendingSyntaxHighlightEditContext = nil
        selectionOccurrenceController.refresh()
        viewportController.handleTextStorageDidEdit(
            textStorage,
            editedRange: editedRange,
            changeInLength: delta
        )
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        viewportController.handleSelectionDidChange()
        searchController.selectionDidChange()
        selectionOccurrenceController.refresh()
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

    @discardableResult
    func performSearchAction(_ action: EditorSearchAction) -> Bool {
        _ = view
        return searchController.perform(action)
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
        currentCursorPosition().line
    }

    func currentCursorPosition() -> EditorCursorPosition {
        viewportController.currentCursorPosition()
    }

    var navigationSelection: NSRange { textView.selectedRange() }

    func restoreNavigationSelection(_ selection: NSRange) {
        // shortcut: checkpoints use character offsets; track edits if exact anchors become necessary.
        let selection = selection.clamped(toLength: (textView.string as NSString).length)
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
        viewportController.handleCaretNavigation()
        focusTextView()
    }

    @discardableResult
    func goToLine(_ lineNumber: Int) -> Bool {
        let previousSelection = textView.selectedRange()
        let result = commandController.goToLine(lineNumber) { [weak self] in
            self?.focusTextView()
        }
        if result { onNavigationCheckpoint?(previousSelection, textView.selectedRange()) }
        return result
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
    }

    private func markdownURL(at index: Int) -> URL? {
        guard syntaxLanguage == .markdown,
              let destination = MarkdownLink.destination(in: textView.string, at: index) else { return nil }
        return MarkdownLink.resolve(destination, relativeTo: documentURLProvider?())
    }

    private func configureTextView() {
        textView.delegate = self
        textView.onNavigationCheckpoint = { [weak self] before, after in
            self?.onNavigationCheckpoint?(before, after)
        }
        searchController.onNavigationCheckpoint = { [weak self] before, after in
            self?.onNavigationCheckpoint?(before, after)
        }
        textView.isCommandClickTarget = { [weak self] index in
            self?.markdownURL(at: index) != nil
        }
        textView.onCommandClick = { [weak self] index in
            guard let self, let url = markdownURL(at: index) else { return false }
            onOpenMarkdownURL(url)
            return true
        }
        textView.onCancelSearch = { [weak self] in
            self?.searchController.perform(.close) ?? false
        }
        textView.onFileSystemURLsDropped = { [weak self] urls in
            self?.onFileSystemURLsDropped?(urls)
        }
        textView.onIndentSelectedLines = { [weak self] in
            self?.commandController.indentSelectedLines() ?? false
        }
        textView.onMoveSelectedLinesUp = { [weak self] in
            self?.moveSelectedLinesUp() ?? false
        }
        textView.onMoveSelectedLinesDown = { [weak self] in
            self?.moveSelectedLinesDown() ?? false
        }

        textView.textStorage?.delegate = self
        scrollView.documentView = textView
        AppPerformanceProfiler.measure("EditorTextViewConfigure") {
            textViewStyler.configureTextView()
        }
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
        selectionOccurrenceController.refresh()
        bracketHighlightController.refresh()
        searchController.panel.applyTheme()
        searchController.refresh()
    }

    private func notifyCursorPositionChanged() {
        onCursorPositionChanged?()
    }

    func dismissFormattingErrorBanner() {
        formattingErrorPresenter.dismiss()
    }
}
