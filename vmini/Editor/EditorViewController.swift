import AppKit

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    private enum Constants {
        static let lineSpacing: CGFloat = 2
        static let formattingErrorBannerHeight: CGFloat = 30
        static let formattingErrorBannerMinimumWidth: CGFloat = 180
        static let formattingErrorBannerHorizontalInset: CGFloat = 12
        static let formattingErrorBannerVerticalGap: CGFloat = 6
        static let formattingErrorBannerMaximumWidth: CGFloat = 560
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
    var onJSONFormattingError: ((String, String) -> Void)?

    private let scrollView = NSScrollView()
    private let formattingErrorBannerView = NSView()
    private let formattingErrorBannerLabel = NSTextField(labelWithString: "")
    private let formattingErrorBannerDismissButton = NSButton(title: "", target: nil, action: nil)
    private let textView = FileDropTextView()
    private let highlighterRegistry = HighlighterRegistry.shared
    private lazy var lineNumberRulerView = LineNumberRulerView(textView: textView)
    private var lineNumberRulerWidthConstraint: NSLayoutConstraint?
    private var hasCompletedInitialViewportReset = false
    private var isApplyingSyntaxHighlighting = false
    private var formattingErrorCharacterLocation: Int?
    private(set) var formattingErrorMessage: String?

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
        applyTheme()
        refreshSyntaxHighlighting()
    }

    private func configureFormattingErrorBanner() {
        formattingErrorBannerView.wantsLayer = true
        formattingErrorBannerView.isHidden = true
        formattingErrorBannerView.frame = NSRect(
            x: 0,
            y: 0,
            width: Constants.formattingErrorBannerMinimumWidth,
            height: Constants.formattingErrorBannerHeight
        )
        formattingErrorBannerView.layer?.cornerRadius = 7
        formattingErrorBannerView.layer?.masksToBounds = true

        formattingErrorBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        formattingErrorBannerLabel.lineBreakMode = .byTruncatingTail
        formattingErrorBannerLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        formattingErrorBannerDismissButton.translatesAutoresizingMaskIntoConstraints = false
        formattingErrorBannerDismissButton.isBordered = false
        formattingErrorBannerDismissButton.bezelStyle = .regularSquare
        formattingErrorBannerDismissButton.imagePosition = .imageOnly
        formattingErrorBannerDismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss formatting error")
        formattingErrorBannerDismissButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        formattingErrorBannerDismissButton.target = self
        formattingErrorBannerDismissButton.action = #selector(dismissFormattingErrorBanner(_:))

        formattingErrorBannerView.addSubview(formattingErrorBannerLabel)
        formattingErrorBannerView.addSubview(formattingErrorBannerDismissButton)
        NSLayoutConstraint.activate([
            formattingErrorBannerLabel.leadingAnchor.constraint(equalTo: formattingErrorBannerView.leadingAnchor, constant: 12),
            formattingErrorBannerLabel.trailingAnchor.constraint(equalTo: formattingErrorBannerDismissButton.leadingAnchor, constant: -8),
            formattingErrorBannerLabel.centerYAnchor.constraint(equalTo: formattingErrorBannerView.centerYAnchor),

            formattingErrorBannerDismissButton.trailingAnchor.constraint(equalTo: formattingErrorBannerView.trailingAnchor, constant: -8),
            formattingErrorBannerDismissButton.centerYAnchor.constraint(equalTo: formattingErrorBannerView.centerYAnchor),
            formattingErrorBannerDismissButton.widthAnchor.constraint(equalToConstant: 18),
            formattingErrorBannerDismissButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        scrollView.contentView.addSubview(formattingErrorBannerView)
        applyFormattingErrorBannerAppearance()
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
        applyFormattingErrorBannerAppearance()
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

    private var lineCommentPrefix: String {
        switch syntaxLanguage {
        case .bash, .sshconfig:
            "#"
        case .plaintext, .markdown, .json:
            "//"
        }
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
        let commentPrefix = lineCommentPrefix
        let prefixLength = (commentPrefix as NSString).length

        repeat {
            let lineRange = text.lineRange(for: NSRange(location: min(lineLocation, text.length), length: 0))
            let hasCommentPrefix = lineRange.location + prefixLength <= text.length
                && text.substring(with: NSRange(location: lineRange.location, length: prefixLength)) == commentPrefix

            edits.append(CommentEdit(
                location: lineRange.location,
                removedLength: hasCommentPrefix ? prefixLength : 0,
                insertedText: hasCommentPrefix ? "" : commentPrefix
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
        formattingErrorMessage = message
        formattingErrorCharacterLocation = characterLocation
        formattingErrorBannerLabel.stringValue = message
        formattingErrorBannerView.isHidden = false
        updateFormattingErrorBannerLayout()
    }

    func dismissFormattingErrorBanner() {
        clearFormattingErrorBanner()
    }

    @objc
    private func dismissFormattingErrorBanner(_ sender: Any?) {
        dismissFormattingErrorBanner()
    }

    private func clearFormattingErrorBanner() {
        guard formattingErrorMessage != nil else {
            return
        }

        formattingErrorMessage = nil
        formattingErrorCharacterLocation = nil
        formattingErrorBannerLabel.stringValue = ""
        formattingErrorBannerView.isHidden = true
    }

    private func applyFormattingErrorBannerAppearance() {
        formattingErrorBannerView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
        formattingErrorBannerLabel.textColor = NSColor.systemRed.blended(withFraction: 0.8, of: AppColors.primaryText) ?? AppColors.primaryText
        formattingErrorBannerDismissButton.contentTintColor = formattingErrorBannerLabel.textColor
    }

    private func updateFormattingErrorBannerLayout() {
        guard
            let message = formattingErrorMessage,
            let clipView = scrollView.contentView as NSClipView?,
            let window = view.window
        else {
            return
        }

        formattingErrorBannerLabel.stringValue = message

        let viewportWidth = clipView.bounds.width
        let bannerWidth = max(
            min(viewportWidth - (Constants.formattingErrorBannerHorizontalInset * 2), Constants.formattingErrorBannerMaximumWidth),
            Constants.formattingErrorBannerMinimumWidth
        )
        let linePoint = pointForFormattingErrorBanner(in: clipView, window: window)
        let x = min(
            max(linePoint.x, Constants.formattingErrorBannerHorizontalInset),
            max(Constants.formattingErrorBannerHorizontalInset, viewportWidth - bannerWidth - Constants.formattingErrorBannerHorizontalInset)
        )
        let y = bannerYPosition(for: linePoint, in: clipView)

        formattingErrorBannerView.frame = NSRect(
            x: x,
            y: y,
            width: bannerWidth,
            height: Constants.formattingErrorBannerHeight
        )
    }

    private func pointForFormattingErrorBanner(in clipView: NSClipView, window: NSWindow) -> NSPoint {
        let textLength = textView.string.utf16.count
        let targetLocation = min(max(formattingErrorCharacterLocation ?? 0, 0), textLength)
        let characterRange = NSRange(location: targetLocation, length: 0)

        let rectInScreen = textView.firstRect(forCharacterRange: characterRange, actualRange: nil)
        let rectInWindow = window.convertFromScreen(rectInScreen)
        return clipView.convert(rectInWindow.origin, from: nil)
    }

    private func bannerYPosition(for linePoint: NSPoint, in clipView: NSClipView) -> CGFloat {
        let topInset = Constants.formattingErrorBannerVerticalGap
        let bottomInset = Constants.formattingErrorBannerVerticalGap
        let maxY = clipView.bounds.height - Constants.formattingErrorBannerHeight - bottomInset

        if clipView.isFlipped {
            return min(
                max(topInset, linePoint.y - Constants.formattingErrorBannerHeight - Constants.formattingErrorBannerVerticalGap),
                maxY
            )
        }

        return max(
            bottomInset,
            min(maxY, linePoint.y + Constants.formattingErrorBannerVerticalGap)
        )
    }
}
