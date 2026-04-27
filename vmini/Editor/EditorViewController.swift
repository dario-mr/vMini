import AppKit

final class EditorViewController: NSViewController, NSTextViewDelegate {
    private enum Constants {
        static let lineSpacing: CGFloat = 2
    }

    var onTextChanged: ((String) -> Void)?
    var onFileSystemURLsDropped: (([URL]) -> Void)?

    private let scrollView = NSScrollView()
    private let textView = FileDropTextView()
    private lazy var lineNumberRulerView = LineNumberRulerView(textView: textView)
    private var hasCompletedInitialViewportReset = false

    var text: String {
        get { textView.string }
        set {
            guard textView.string != newValue else { return }
            textView.string = newValue
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            hasCompletedInitialViewportReset = false
            if isViewLoaded {
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

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
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
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
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
        lineNumberRulerView.invalidateLineNumbers()
        synchronizeWordWrapLayout()
        onTextChanged?(textView.string)
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

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
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
        textView.onFileSystemURLsDropped = { [weak self] urls in
            self?.onFileSystemURLsDropped?(urls)
        }
        applyEditorFontSize(EditorSettings.currentFontSize())
        applyParagraphStyle()
        textView.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.20, alpha: 1.0)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 12, height: 12)

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        // Future syntax highlighting should flow through NSTextStorage attributes in one place.
        scrollView.documentView = textView
        applyEditorWordWrap(EditorSettings.isWordWrapEnabled())
    }

    private func configureLineNumberRuler() {
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = lineNumberRulerView
        lineNumberRulerView.invalidateLineNumbers()
    }

    private func applyEditorFontSize(_ fontSize: CGFloat) {
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
        let rulerCompensation = scrollView.hasVerticalRuler ? lineNumberRulerView.ruleThickness : 0
        return max(scrollView.contentSize.width - rulerCompensation, 1)
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
        scrollView.hasVerticalRuler ? -lineNumberRulerView.ruleThickness : 0
    }
}
