import AppKit

@MainActor
final class EditorTabBarController {
    private struct TabDragState {
        let document: Document
        let tabView: DocumentTabView
        let pointerOffset: CGFloat
    }

    let view = NSView()

    var onSelectDocument: ((Document) -> Void)?
    var onCloseDocument: ((Document) -> Void)?
    var onCloseOtherDocuments: ((Document) -> Void)?
    var onCloseAllDocuments: (() -> Void)?
    var onCreateNewDocument: (() -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = TabContentBackgroundView()
    private var tabViewsByDocumentIdentifier: [ObjectIdentifier: DocumentTabView] = [:]
    private var currentTabDrag: TabDragState?
    private var activeTabView: NSView?
    private var lastDocumentIdentifiers: [ObjectIdentifier] = []
    private var lastActiveDocumentIdentifier: ObjectIdentifier?

    init() {
        configureView()
    }

    func update(documents: [Document], activeDocument: Document?) {
        let nextDocumentIdentifiers = documents.map(ObjectIdentifier.init)
        let nextActiveDocumentIdentifier = activeDocument.map(ObjectIdentifier.init)
        let liveIdentifiers = Set(documents.map(ObjectIdentifier.init))

        for (identifier, tabView) in tabViewsByDocumentIdentifier where !liveIdentifiers.contains(identifier) {
            if currentTabDrag?.document === tabView.document {
                currentTabDrag = nil
            }
            tabView.removeFromSuperview()
            tabViewsByDocumentIdentifier.removeValue(forKey: identifier)
        }

        let dragChangedOrder = currentTabDrag != nil
        let documentOrderChanged = nextDocumentIdentifiers != lastDocumentIdentifiers
        let activeDocumentChanged = nextActiveDocumentIdentifier != lastActiveDocumentIdentifier

        for document in documents {
            let identifier = ObjectIdentifier(document)
            let tabView = tabViewsByDocumentIdentifier[identifier] ?? makeTabView(for: document)
            tabView.configure(document: document, isActive: document === activeDocument)

            if tabView.superview == nil {
                contentView.addSubview(tabView)
            }
        }

        layoutTabViews(
            documents: documents,
            activeDocument: activeDocument,
            animated: dragChangedOrder,
            shouldScrollActiveTab: documentOrderChanged || activeDocumentChanged
        )
        lastDocumentIdentifiers = nextDocumentIdentifiers
        lastActiveDocumentIdentifier = nextActiveDocumentIdentifier
    }

    func refreshTheme() {
        view.layer?.backgroundColor = AppColors.tabBarBackground.cgColor
        contentView.layer?.backgroundColor = AppColors.tabBarBackground.cgColor
        for tabView in tabViewsByDocumentIdentifier.values {
            tabView.refreshAppearance()
        }
    }

    func scrollActiveTabToVisible() {
        guard let activeTabView else { return }
        scrollTabViewToVisible(activeTabView)
    }

    private func configureView() {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = AppColors.tabBarBackground.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = AppColors.tabBarBackground.cgColor
        contentView.onDoubleClickEmptyArea = { [weak self] in
            self?.onCreateNewDocument?()
        }

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: EditorTabBarLayout.tabBarHeight),
        ])

        scrollView.documentView = contentView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeTabView(for document: Document) -> DocumentTabView {
        let tabView = DocumentTabView()
        tabView.configure(document: document, isActive: false)
        tabView.onSelect = { [weak self] document in
            self?.onSelectDocument?(document)
        }
        tabView.onClose = { [weak self] document in
            self?.onCloseDocument?(document)
        }
        tabView.onCloseOthers = { [weak self] document in
            self?.onCloseOtherDocuments?(document)
        }
        tabView.onCloseAll = { [weak self] in
            self?.onCloseAllDocuments?()
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

    private func layoutTabViews(
        documents: [Document],
        activeDocument: Document?,
        animated: Bool,
        shouldScrollActiveTab: Bool
    ) {
        var nextMinX = EditorTabBarLayout.tabBarHorizontalInset
        var resolvedActiveTabView: NSView?

        for document in documents {
            let identifier = ObjectIdentifier(document)
            guard let tabView = tabViewsByDocumentIdentifier[identifier] else { continue }

            let frame = NSRect(
                x: nextMinX,
                y: 0,
                width: tabView.preferredWidth(),
                height: EditorTabBarLayout.tabHeight
            )

            if let currentTabDrag, currentTabDrag.document === document {
                tabView.frame.size = frame.size
            } else {
                applyTabFrame(frame, to: tabView, animated: animated)
            }

            if document === activeDocument {
                resolvedActiveTabView = tabView
            }
            nextMinX = frame.maxX
        }

        contentView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(scrollView.contentSize.width, nextMinX + EditorTabBarLayout.tabBarHorizontalInset),
            height: EditorTabBarLayout.tabBarHeight
        )

        activeTabView = resolvedActiveTabView
        if shouldScrollActiveTab, let resolvedActiveTabView {
            scrollTabViewToVisible(resolvedActiveTabView)
        }
    }

    private func scrollTabViewToVisible(_ tabView: NSView) {
        guard let documentView = scrollView.documentView else { return }
        let rectInDocument = documentView.convert(tabView.frame, from: tabView.superview)
        scrollView.contentView.scrollToVisible(rectInDocument.insetBy(dx: -24, dy: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func beginTabDrag(for tabView: DocumentTabView, locationInWindow: NSPoint) {
        guard let document = tabView.document else { return }
        let locationInContent = contentView.convert(locationInWindow, from: nil)
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

        let locationInContent = contentView.convert(locationInWindow, from: nil)
        let minX = EditorTabBarLayout.tabBarHorizontalInset
        let maxX = max(minX, contentView.frame.width - tabView.frame.width - EditorTabBarLayout.tabBarHorizontalInset)
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
        guard let documentView = scrollView.documentView else { return }
        let rectInDocument = documentView.convert(tabView.frame, from: tabView.superview)
        scrollView.contentView.scrollToVisible(rectInDocument.insetBy(dx: -24, dy: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func finishTabDrag(for tabView: DocumentTabView) {
        guard let document = tabView.document else { return }
        guard currentTabDrag?.document === document else {
            return
        }

        currentTabDrag = nil
        tabView.layer?.zPosition = 0
        update(documents: OpenDocumentsStore.shared.documents, activeDocument: OpenDocumentsStore.shared.activeDocument)
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
}
