import AppKit

private enum TabLayout {
    static let minimumTabWidth: CGFloat = 160
    static let maximumTabWidth: CGFloat = 240
    static let tabBarHeight: CGFloat = 30
    static let tabHeight: CGFloat = 28
    static let tabBarHorizontalInset: CGFloat = 2
}

private final class TabContentBackgroundView: NSView {
    var onDoubleClickEmptyArea: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClickEmptyArea?()
            return
        }

        super.mouseDown(with: event)
    }
}

private final class DocumentTabView: NSView {
    private enum Layout {
        static let titleLeadingInset: CGFloat = 12
        static let titleToCloseButtonSpacing: CGFloat = 12
        static let closeButtonTrailingInset: CGFloat = 10
        static let closeButtonSize: CGFloat = 12
    }

    private enum Typography {
        static let fontSize: CGFloat = 12
        static let activeWeight: NSFont.Weight = .regular
        static let inactiveWeight: NSFont.Weight = .regular
    }

    weak var document: Document?

    var onSelect: ((Document) -> Void)?
    var onClose: ((Document) -> Void)?
    var onCloseOthers: ((Document) -> Void)?
    var onCloseAll: (() -> Void)?
    var onDragStarted: ((DocumentTabView, NSPoint) -> Void)?
    var onDragMoved: ((DocumentTabView, NSPoint) -> Void)?
    var onDragEnded: ((DocumentTabView) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isActive = false
    private var dragStartLocationInWindow: NSPoint?
    private var isDraggingTab = false
    private let hoverFadeDuration: CFTimeInterval = 0.16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        closeButton.target = self
        closeButton.action = #selector(handleCloseButton)
        closeButton.contentTintColor = AppColors.defaultControlTint
        closeButton.setButtonType(.momentaryChange)

        addSubview(titleLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: TabLayout.tabHeight),
            widthAnchor.constraint(greaterThanOrEqualToConstant: TabLayout.minimumTabWidth),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.titleLeadingInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -Layout.titleToCloseButtonSpacing),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.closeButtonTrailingInset),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Layout.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Layout.closeButtonSize),
        ])

    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseDown(with event: NSEvent) {
        guard let document else { return }
        dragStartLocationInWindow = event.locationInWindow
        isDraggingTab = false
        onSelect?(document)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartLocationInWindow else { return }

        let deltaX = event.locationInWindow.x - dragStartLocationInWindow.x
        let deltaY = event.locationInWindow.y - dragStartLocationInWindow.y
        if !isDraggingTab, hypot(deltaX, deltaY) >= 4 {
            isDraggingTab = true
            onDragStarted?(self, event.locationInWindow)
        }

        guard isDraggingTab else { return }
        onDragMoved?(self, event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartLocationInWindow = nil
            isDraggingTab = false
        }

        guard isDraggingTab else { return }
        onDragEnded?(self)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let document else {
            super.otherMouseUp(with: event)
            return
        }

        onClose?(document)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard document != nil else {
            super.rightMouseDown(with: event)
            return
        }

        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearance()
    }

    func refreshAppearance() {
        applyAppearance()
    }

    func configure(document: Document, isActive: Bool) {
        self.document = document
        self.isActive = isActive
        titleLabel.stringValue = document.shortDisplayTitle
        applyAppearance()
    }

    func preferredWidth() -> CGFloat {
        let titleWidth = ceil(titleLabel.intrinsicContentSize.width)
        let contentWidth = Layout.titleLeadingInset
            + titleWidth
            + Layout.titleToCloseButtonSpacing
            + Layout.closeButtonSize
            + Layout.closeButtonTrailingInset
        return min(max(contentWidth, TabLayout.minimumTabWidth), TabLayout.maximumTabWidth)
    }

    private func applyAppearance() {
        guard let layer else { return }

        layer.masksToBounds = true
        layer.cornerRadius = 0
        layer.mask = makeTopRoundedMaskLayer()

        if isActive {
            setBackgroundColor(AppColors.editorBackground.cgColor, animated: false)
            titleLabel.textColor = AppColors.primaryText
            titleLabel.font = NSFont.systemFont(ofSize: Typography.fontSize, weight: Typography.activeWeight)
            closeButton.contentTintColor = AppColors.activeControlTint
        } else {
            let backgroundColor = (isHovered
                ? AppColors.hoveredTabBackground
                : AppColors.tabBarBackground).cgColor
            setBackgroundColor(backgroundColor, animated: true)
            titleLabel.textColor = isHovered ? AppColors.sidebarText : AppColors.inactiveTabText
            titleLabel.font = NSFont.systemFont(ofSize: Typography.fontSize, weight: Typography.inactiveWeight)
            closeButton.contentTintColor = isHovered ? AppColors.hoveredControlTint : AppColors.inactiveControlTint
        }
    }

    private func setBackgroundColor(_ color: CGColor, animated: Bool) {
        guard let layer else { return }
        let previousColor = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        layer.backgroundColor = color

        guard
            animated,
            let previousColor,
            previousColor != color
        else {
            return
        }

        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = previousColor
        animation.toValue = color
        animation.duration = hoverFadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "backgroundColorFade")
    }

    override func layout() {
        super.layout()
        layer?.mask = makeTopRoundedMaskLayer()
    }

    private func makeTopRoundedMaskLayer() -> CAShapeLayer {
        let radius: CGFloat = 6
        let rect = bounds
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()

        let maskLayer = CAShapeLayer()
        maskLayer.frame = rect
        maskLayer.path = path
        return maskLayer
    }

    @objc
    private func handleCloseButton() {
        guard let document else { return }
        onClose?(document)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Close", action: #selector(closeFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close Others", action: #selector(closeOthersFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close All", action: #selector(closeAllFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy Path", action: #selector(copyPathFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show in Finder", action: #selector(showInFinderFromMenu), keyEquivalent: ""))

        for item in menu.items {
            item.target = self
        }

        return menu
    }

    @objc
    private func closeFromMenu() {
        guard let document else { return }
        onClose?(document)
    }

    @objc
    private func closeOthersFromMenu() {
        guard let document else { return }
        onCloseOthers?(document)
    }

    @objc
    private func closeAllFromMenu() {
        onCloseAll?()
    }

    @objc
    private func copyPathFromMenu() {
        guard let path = document?.fileURL?.path else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    @objc
    private func showInFinderFromMenu() {
        guard let fileURL = document?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}

extension DocumentTabView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copyPathFromMenu)
            || menuItem.action == #selector(showInFinderFromMenu) {
            return document?.fileURL != nil
        }

        return true
    }
}

final class EditorContentViewController: NSViewController {
    private struct TabDragState {
        let document: Document
        let tabView: DocumentTabView
        let pointerOffset: CGFloat
    }

    fileprivate enum Constants {
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarMaxWidth: CGFloat = 420
        static let sidebarDefaultWidth: CGFloat = 300
        static let resizeHandleWidth: CGFloat = 12
    }

    private let tabBarContainer = NSView()
    private let tabScrollView = NSScrollView()
    private let tabContentView = TabContentBackgroundView()
    private let sidebarViewController = OpenFilesSidebarViewController()
    private let editorContainerView = NSView()
    private let statusBarView = EditorStatusBarView()
    private let fontSizeHUDView = FontSizeHUDView()
    private let resizeHandle = ResizeHandleView()
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var dragStartWidth: CGFloat = 0
    private var currentEditorViewController: EditorViewController?
    private var tabViewsByDocumentIdentifier: [ObjectIdentifier: DocumentTabView] = [:]
    private var currentTabDrag: TabDragState?

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let contentView = FileDropContentView()
        contentView.dropDelegate = self
        view = contentView
        view.wantsLayer = true
        view.layer?.backgroundColor = AppColors.appBackground.cgColor

        addChild(sidebarViewController)

        let sidebarView = sidebarViewController.view
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        editorContainerView.translatesAutoresizingMaskIntoConstraints = false
        editorContainerView.wantsLayer = true
        editorContainerView.layer?.backgroundColor = AppColors.editorBackground.cgColor
        editorContainerView.layer?.masksToBounds = true
        configureStatusBar()
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        configureTabBar()

        view.addSubview(sidebarView)
        view.addSubview(editorContainerView)
        view.addSubview(tabBarContainer)
        view.addSubview(statusBarView)
        view.addSubview(fontSizeHUDView)
        view.addSubview(resizeHandle)

        let widthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: storedSidebarWidth())
        sidebarWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            widthConstraint,

            tabBarContainer.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            tabBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarContainer.heightAnchor.constraint(equalToConstant: TabLayout.tabBarHeight),

            editorContainerView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            editorContainerView.topAnchor.constraint(equalTo: tabBarContainer.bottomAnchor),
            editorContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorContainerView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),

            statusBarView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: EditorStatusBarView.Layout.preferredHeight),

            fontSizeHUDView.centerXAnchor.constraint(equalTo: editorContainerView.centerXAnchor),
            fontSizeHUDView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor, constant: -12),

            resizeHandle.centerXAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: view.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: Constants.resizeHandleWidth),
        ])

        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleSidebarResize(_:)))
        resizeHandle.addGestureRecognizer(panGesture)
        resizeHandle.cursor = .resizeLeftRight
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentsDidChange),
            name: OpenDocumentsStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentSyntaxHighlightingDidChange(_:)),
            name: .documentSyntaxHighlightingDidChange,
            object: nil
        )
    }

    func increaseEditorFontSize() {
        currentEditorViewController?.increaseFontSize()
        showFontSizeHUD()
    }

    func decreaseEditorFontSize() {
        currentEditorViewController?.decreaseFontSize()
        showFontSizeHUD()
    }

    func focusActiveEditor() {
        currentEditorViewController?.focusTextView()
    }

    func toggleLineComment() {
        currentEditorViewController?.toggleLineComment()
    }

    func duplicateSelectedLines() {
        currentEditorViewController?.duplicateSelectedLines()
    }

    func deleteCurrentLine() {
        currentEditorViewController?.deleteCurrentLine()
    }

    @discardableResult
    func moveSelectedLinesUp() -> Bool {
        currentEditorViewController?.moveSelectedLinesUp() ?? false
    }

    @discardableResult
    func moveSelectedLinesDown() -> Bool {
        currentEditorViewController?.moveSelectedLinesDown() ?? false
    }

    func formatJSON() {
        currentEditorViewController?.formatJSONSelectionOrDocument()
    }

    func currentLineNumber() -> Int {
        currentEditorViewController?.currentLineNumber() ?? 1
    }

    @discardableResult
    func goToLine(_ lineNumber: Int) -> Bool {
        currentEditorViewController?.goToLine(lineNumber) ?? false
    }

    private func storedSidebarWidth() -> CGFloat {
        let width = UserDefaults.standard.double(forKey: UserDefaultsKeys.openFilesSidebarWidth)
        guard width > 0 else { return Constants.sidebarDefaultWidth }
        return min(max(width, Constants.sidebarMinWidth), Constants.sidebarMaxWidth)
    }

    @objc
    private func handleSidebarResize(_ gestureRecognizer: NSPanGestureRecognizer) {
        guard let sidebarWidthConstraint else { return }

        switch gestureRecognizer.state {
        case .began:
            dragStartWidth = sidebarWidthConstraint.constant
        case .changed:
            let translation = gestureRecognizer.translation(in: view).x
            let proposedWidth = dragStartWidth + translation
            sidebarWidthConstraint.constant = min(max(proposedWidth, Constants.sidebarMinWidth), Constants.sidebarMaxWidth)
        case .ended, .cancelled:
            let finalWidth = min(max(sidebarWidthConstraint.constant, Constants.sidebarMinWidth), Constants.sidebarMaxWidth)
            sidebarWidthConstraint.constant = finalWidth
            UserDefaults.standard.set(finalWidth, forKey: UserDefaultsKeys.openFilesSidebarWidth)
        default:
            break
        }
    }

    private func configureTabBar() {
        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.wantsLayer = true
        tabBarContainer.layer?.backgroundColor = AppColors.tabBarBackground.cgColor

        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.drawsBackground = false
        tabScrollView.borderType = .noBorder
        tabScrollView.hasVerticalScroller = false
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.autohidesScrollers = true
        tabScrollView.scrollerStyle = .overlay

        tabContentView.translatesAutoresizingMaskIntoConstraints = false
        tabContentView.wantsLayer = true
        tabContentView.layer?.backgroundColor = AppColors.tabBarBackground.cgColor
        tabContentView.onDoubleClickEmptyArea = { [weak self] in
            self?.createNewTabFromTabBar()
        }
        NSLayoutConstraint.activate([
            tabContentView.heightAnchor.constraint(equalToConstant: TabLayout.tabBarHeight),
        ])

        tabScrollView.documentView = tabContentView
        tabBarContainer.addSubview(tabScrollView)

        NSLayoutConstraint.activate([
            tabScrollView.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor),
            tabScrollView.topAnchor.constraint(equalTo: tabBarContainer.topAnchor),
            tabScrollView.bottomAnchor.constraint(equalTo: tabBarContainer.bottomAnchor),
        ])
    }

    private func createNewTabFromTabBar() {
        (NSApp.delegate as? AppDelegate)?.newDocument(tabContentView)
    }

    private func configureStatusBar() {
        statusBarView.onSelectAutomaticSyntaxHighlighting = { [weak self] in
            self?.selectAutomaticSyntaxHighlighting()
        }
        statusBarView.onSelectSyntaxHighlightingOverride = { [weak self] language in
            self?.selectSyntaxHighlightingOverride(language)
        }
        updateStatusBar()
    }

    @objc
    private func handleDocumentsDidChange() {
        syncWorkspace()
    }

    @objc
    private func handleThemeDidChange() {
        applyTheme()
        for tabView in tabViewsByDocumentIdentifier.values {
            tabView.refreshAppearance()
        }
        updateStatusBar()
    }

    @objc
    private func handleDocumentSyntaxHighlightingDidChange(_ notification: Notification) {
        guard let document = notification.object as? Document else { return }
        guard document === OpenDocumentsStore.shared.activeDocument else { return }
        updateStatusBar()
    }

    private func applyTheme() {
        view.layer?.backgroundColor = AppColors.appBackground.cgColor
        editorContainerView.layer?.backgroundColor = AppColors.editorBackground.cgColor
        tabBarContainer.layer?.backgroundColor = AppColors.tabBarBackground.cgColor
        tabContentView.layer?.backgroundColor = AppColors.tabBarBackground.cgColor
        statusBarView.applyTheme()
        fontSizeHUDView.applyTheme()
    }

    private func showFontSizeHUD() {
        guard currentEditorViewController != nil else { return }
        fontSizeHUDView.show(fontSize: EditorSettings.currentFontSize())
    }

    private func syncWorkspace() {
        if OpenDocumentsStore.shared.activeDocument == nil {
            OpenDocumentsStore.shared.select(OpenDocumentsStore.shared.documents.first)
        }

        synchronizeTabViews()
        displayActiveDocumentIfNeeded()
    }

    private func synchronizeTabViews() {
        let documents = OpenDocumentsStore.shared.documents
        let activeDocument = OpenDocumentsStore.shared.activeDocument
        let liveIdentifiers = Set(documents.map(ObjectIdentifier.init))

        for (identifier, tabView) in tabViewsByDocumentIdentifier where !liveIdentifiers.contains(identifier) {
            if currentTabDrag?.document === tabView.document {
                currentTabDrag = nil
            }
            tabView.removeFromSuperview()
            tabViewsByDocumentIdentifier.removeValue(forKey: identifier)
        }

        let dragChangedOrder = currentTabDrag != nil
        for document in documents {
            let identifier = ObjectIdentifier(document)
            let tabView = tabViewsByDocumentIdentifier[identifier] ?? makeTabView(for: document)
            tabView.configure(document: document, isActive: document === activeDocument)

            if tabView.superview == nil {
                tabContentView.addSubview(tabView)
            }
        }

        layoutTabViews(animated: dragChangedOrder)
    }

    private func makeTabView(for document: Document) -> DocumentTabView {
        let tabView = DocumentTabView()
        tabView.configure(document: document, isActive: document === OpenDocumentsStore.shared.activeDocument)
        tabView.onSelect = { [weak self] document in
            self?.present(document)
        }
        tabView.onClose = { [weak self] document in
            self?.close(document)
        }
        tabView.onCloseOthers = { [weak self] document in
            self?.closeAll(except: document)
        }
        tabView.onCloseAll = { [weak self] in
            self?.closeAll()
        }
        tabView.onDragStarted = { [weak self] tabView, locationInWindow in
            self?.beginTabDrag(for: tabView, locationInWindow: locationInWindow)
        }
        tabView.onDragMoved = { [weak self] tabView, locationInWindow in
            self?.updateTabDrag(for: tabView, locationInWindow: locationInWindow)
        }
        tabView.onDragEnded = { [weak self] tabView in
            self?.finishTabDrag(for: tabView)
        }
        tabViewsByDocumentIdentifier[ObjectIdentifier(document)] = tabView
        return tabView
    }

    private func layoutTabViews(animated: Bool) {
        let activeDocument = OpenDocumentsStore.shared.activeDocument
        let documents = OpenDocumentsStore.shared.documents
        var nextMinX = TabLayout.tabBarHorizontalInset
        var activeTabView: NSView?

        for document in documents {
            let identifier = ObjectIdentifier(document)
            guard let tabView = tabViewsByDocumentIdentifier[identifier] else { continue }

            let frame = NSRect(
                x: nextMinX,
                y: 0,
                width: tabView.preferredWidth(),
                height: TabLayout.tabHeight
            )

            if let currentTabDrag, currentTabDrag.document === document {
                tabView.frame.size = frame.size
            } else {
                applyTabFrame(frame, to: tabView, animated: animated)
            }

            if document === activeDocument {
                activeTabView = tabView
            }
            nextMinX = frame.maxX
        }

        tabContentView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(tabScrollView.contentSize.width, nextMinX + TabLayout.tabBarHorizontalInset),
            height: TabLayout.tabBarHeight
        )

        if let activeTabView {
            scrollTabViewToVisible(activeTabView)
        }
    }

    private func scrollTabViewToVisible(_ tabView: NSView) {
        guard let documentView = tabScrollView.documentView else { return }
        let rectInDocument = documentView.convert(tabView.frame, from: tabView.superview)
        tabScrollView.contentView.scrollToVisible(rectInDocument.insetBy(dx: -24, dy: 0))
        tabScrollView.reflectScrolledClipView(tabScrollView.contentView)
    }

    private func beginTabDrag(for tabView: DocumentTabView, locationInWindow: NSPoint) {
        guard let document = tabView.document else { return }
        let locationInContent = tabContentView.convert(locationInWindow, from: nil)
        let pointerOffset = locationInContent.x - tabView.frame.minX
        currentTabDrag = TabDragState(document: document, tabView: tabView, pointerOffset: pointerOffset)
        tabView.layer?.zPosition = 10
    }

    private func updateTabDrag(for tabView: DocumentTabView, locationInWindow: NSPoint) {
        guard
            let document = tabView.document,
            let currentTabDrag,
            currentTabDrag.document === document
        else {
            return
        }

        let locationInContent = tabContentView.convert(locationInWindow, from: nil)
        let minX = TabLayout.tabBarHorizontalInset
        let maxX = max(minX, tabContentView.frame.width - tabView.frame.width - TabLayout.tabBarHorizontalInset)
        let clampedMinX = min(max(locationInContent.x - currentTabDrag.pointerOffset, minX), maxX)
        tabView.frame.origin.x = clampedMinX
        tabView.frame.origin.y = 0

        reorderTabIfNeeded(for: document, draggedMidX: tabView.frame.midX)
        autoscrollDraggedTabIfNeeded(tabView)
    }

    private func reorderTabIfNeeded(for document: Document, draggedMidX: CGFloat) {
        let orderedDocuments = OpenDocumentsStore.shared.documents
        guard
            let sourceIndex = orderedDocuments.firstIndex(where: { $0 === document }),
            orderedDocuments.count > 1
        else {
            return
        }

        var destinationIndex = 0
        for candidate in orderedDocuments where candidate !== document {
            guard let candidateTabView = tabViewsByDocumentIdentifier[ObjectIdentifier(candidate)] else { continue }
            if draggedMidX > candidateTabView.frame.midX {
                destinationIndex += 1
            }
        }

        let targetIndex = min(max(destinationIndex, 0), orderedDocuments.count - 1)
        guard targetIndex != sourceIndex else { return }

        OpenDocumentsStore.shared.reorder(document: document, to: targetIndex)
    }

    private func autoscrollDraggedTabIfNeeded(_ tabView: NSView) {
        guard let documentView = tabScrollView.documentView else { return }
        let rectInDocument = documentView.convert(tabView.frame, from: tabView.superview)
        tabScrollView.contentView.scrollToVisible(rectInDocument.insetBy(dx: -24, dy: 0))
        tabScrollView.reflectScrolledClipView(tabScrollView.contentView)
    }

    private func finishTabDrag(for tabView: DocumentTabView) {
        guard let document = tabView.document else { return }
        guard currentTabDrag?.document === document else {
            return
        }

        currentTabDrag = nil
        tabView.layer?.zPosition = 0
        layoutTabViews(animated: true)
        scrollTabViewToVisible(tabView)
        SessionRestorer.saveOpenFiles()
    }

    private func applyTabFrame(_ frame: NSRect, to tabView: NSView, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                tabView.animator().frame = frame
            }
        } else {
            tabView.frame = frame
        }
    }

    private func present(_ document: Document) {
        WorkspaceWindowController.shared.present(document: document)
    }

    private func close(_ document: Document) {
        WorkspaceWindowController.shared.close(document: document)
    }

    private func closeAll(except documentToKeep: Document) {
        close(OpenDocumentsStore.shared.documents.filter { $0 !== documentToKeep })
    }

    private func closeAll() {
        close(OpenDocumentsStore.shared.documents)
    }

    private func close(_ documents: [Document]) {
        for document in documents {
            WorkspaceWindowController.shared.close(document: document)
        }
    }

    private func displayActiveDocumentIfNeeded() {
        guard let document = OpenDocumentsStore.shared.activeDocument else {
            currentEditorViewController?.view.removeFromSuperview()
            currentEditorViewController?.removeFromParent()
            currentEditorViewController = nil
            updateStatusBar()
            return
        }

        let editorViewController = document.resolvedEditorViewController { [weak self] urls in
            self?.openFileSystemURLs(urls)
        }
        editorViewController.onCursorPositionChanged = { [weak self] in
            self?.updateStatusBar()
        }
        guard currentEditorViewController !== editorViewController else {
            updateStatusBar()
            editorViewController.focusTextView()
            return
        }

        currentEditorViewController?.view.removeFromSuperview()
        currentEditorViewController?.removeFromParent()

        currentEditorViewController = editorViewController
        addChild(editorViewController)
        let editorView = editorViewController.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorContainerView.addSubview(editorView)
        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: editorContainerView.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: editorContainerView.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: editorContainerView.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: editorContainerView.bottomAnchor),
        ])
        updateStatusBar()
        editorViewController.focusTextView()
    }

    private func updateStatusBar() {
        guard let document = OpenDocumentsStore.shared.activeDocument else {
            statusBarView.update(state: nil)
            return
        }

        statusBarView.update(state: EditorStatusBarState(
            title: document.syntaxOverrideMenuTitle,
            autoDetectedSyntaxLanguage: document.autoDetectedSyntaxLanguage,
            selectedSyntaxLanguage: document.syntaxLanguage,
            hasOverride: document.hasSyntaxLanguageOverride,
            cursorPosition: currentEditorViewController?.currentCursorPosition() ?? EditorCursorPosition(line: 1, column: 1)
        ))
    }

    private func selectAutomaticSyntaxHighlighting() {
        OpenDocumentsStore.shared.activeDocument?.setSyntaxLanguageOverride(nil)
    }

    private func selectSyntaxHighlightingOverride(_ language: SyntaxLanguage) {
        OpenDocumentsStore.shared.activeDocument?.setSyntaxLanguageOverride(language)
    }
}

extension EditorContentViewController: FileDropContentViewDelegate {
    func fileDropContentView(_ view: FileDropContentView, didReceiveFileSystemURLs urls: [URL]) {
        openFileSystemURLs(urls)
    }

    private func openFileSystemURLs(_ urls: [URL]) {
        OpenURLRouter.open(urls, tabbedIn: view.window)
    }
}
