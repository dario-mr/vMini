import AppKit

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    private enum Constants {
        static let lineSpacing: CGFloat = 2
    }

    private struct CommentEdit {
        let location: Int
        let removedLength: Int
        let insertedText: String

        var insertedLength: Int {
            (insertedText as NSString).length
        }
    }

    var onTextChanged: (() -> Void)?
    var onFileSystemURLsDropped: (([URL]) -> Void)?

    private let scrollView = NSScrollView()
    private let textView = FileDropTextView()
    private let highlighterRegistry = HighlighterRegistry.shared
    private lazy var lineNumberRulerView = LineNumberRulerView(textView: textView)
    private var lineNumberRulerWidthConstraint: NSLayoutConstraint?
    private var hasCompletedInitialViewportReset = false
    private var isApplyingSyntaxHighlighting = false

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
            selector: #selector(handleSharedFontSizeChange),
            name: EditorSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSharedWordWrapChange),
            name: EditorSettings.wordWrapDidChangeNotification,
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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func textDidChange(_ notification: Notification) {
        synchronizeWordWrapLayout()
        onTextChanged?()
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

        let selectedRange = textView.selectedRange()
        let text = textView.string as NSString
        let affectedRange = affectedLineRange(in: text, selectedRange: selectedRange)
        let edits = commentEdits(in: text, affectedRange: affectedRange)
        guard !edits.isEmpty else { return }

        let replacement = NSMutableString(string: text.substring(with: affectedRange))
        for edit in edits.reversed() {
            replacement.replaceCharacters(
                in: NSRange(location: edit.location - affectedRange.location, length: edit.removedLength),
                with: edit.insertedText
            )
        }

        let replacementString = replacement as String
        guard textView.shouldChangeText(in: affectedRange, replacementString: replacementString) else {
            return
        }

        let newSelectionStart = transformedPosition(selectedRange.location, byApplying: edits)
        let newSelectionEnd = transformedPosition(NSMaxRange(selectedRange), byApplying: edits)
        let newSelectedRange = NSRange(
            location: min(newSelectionStart, newSelectionEnd),
            length: abs(newSelectionEnd - newSelectionStart)
        )

        textStorage.replaceCharacters(in: affectedRange, with: replacementString)
        textView.didChangeText()
        textView.setSelectedRange(newSelectedRange)
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
        applyEditorFontSize(EditorSettings.currentFontSize())
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
        applyTheme()
        refreshSyntaxHighlighting()
    }

    private func configureLineNumberRuler() {
        lineNumberRulerView.onRuleThicknessChanged = { [weak self] ruleThickness in
            self?.lineNumberRulerWidthConstraint?.constant = ruleThickness
            self?.synchronizeWordWrapLayout()
        }
        lineNumberRulerView.invalidateLineNumbers()
    }

    private func applyEditorFontSize(_ fontSize: CGFloat) {
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .light)
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
    private func handleSharedFontSizeChange() {
        applySharedFontSize()
    }

    @objc
    private func handleSharedWordWrapChange() {
        applyEditorWordWrap(EditorSettings.isWordWrapEnabled())
    }

    @objc
    private func handleScrollBoundsChange() {
        lineNumberRulerView.needsDisplay = true
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
    }

    private func applySharedFontSize() {
        applyEditorFontSize(EditorSettings.currentFontSize())
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

    private func affectedLineRange(in text: NSString, selectedRange: NSRange) -> NSRange {
        let textLength = text.length
        let selectedLocation = min(selectedRange.location, textLength)

        guard selectedRange.length > 0 else {
            return text.lineRange(for: NSRange(location: selectedLocation, length: 0))
        }

        let selectionEnd = min(NSMaxRange(selectedRange), textLength)
        let lastSelectedCharacter = max(selectedLocation, selectionEnd - 1)
        let firstLineRange = text.lineRange(for: NSRange(location: selectedLocation, length: 0))
        let lastLineRange = text.lineRange(for: NSRange(location: lastSelectedCharacter, length: 0))
        return NSRange(
            location: firstLineRange.location,
            length: NSMaxRange(lastLineRange) - firstLineRange.location
        )
    }

    private func commentEdits(in text: NSString, affectedRange: NSRange) -> [CommentEdit] {
        let affectedEnd = NSMaxRange(affectedRange)
        var edits: [CommentEdit] = []
        var lineLocation = affectedRange.location

        repeat {
            let lineRange = text.lineRange(for: NSRange(location: min(lineLocation, text.length), length: 0))
            let hasCommentPrefix = lineRange.location + 2 <= text.length
                && text.substring(with: NSRange(location: lineRange.location, length: 2)) == "//"

            edits.append(CommentEdit(
                location: lineRange.location,
                removedLength: hasCommentPrefix ? 2 : 0,
                insertedText: hasCommentPrefix ? "" : "//"
            ))

            let nextLineLocation = NSMaxRange(lineRange)
            guard nextLineLocation > lineLocation else {
                break
            }

            lineLocation = nextLineLocation
        } while lineLocation < affectedEnd

        return edits
    }

    private func transformedPosition(_ position: Int, byApplying edits: [CommentEdit]) -> Int {
        var delta = 0

        for edit in edits {
            if position < edit.location {
                break
            }

            if edit.removedLength > 0, position <= edit.location + edit.removedLength {
                return edit.location + delta + min(position - edit.location, edit.insertedLength)
            }

            delta += edit.insertedLength - edit.removedLength
        }

        return position + delta
    }
}
