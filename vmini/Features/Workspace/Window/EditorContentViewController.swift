import AppKit

final class EditorContentViewController: NSViewController {
    private let sidebarViewController = OpenFilesSidebarViewController()
    private let tabBarController = EditorTabBarController()
    private let editorContainerView = NSView()
    private let statusBarView = EditorStatusBarView()
    private let fontSizeHUDView = FontSizeHUDView()
    private let resizeHandle = ResizeHandleView()
    private let sidebarResizer = OpenFilesSidebarResizer()
    private let documentStore: OpenDocumentsStore
    private let documentRouter: WorkspaceDocumentRouting
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var activeEditorCoordinator: ActiveEditorCoordinator?
    private var documentsObservation: ObservationToken?
    private var themeObservation: ObservationToken?
    private var activeDocumentSyntaxObservation: ObservationToken?
    private var documentState = OpenDocumentsStore.State(documents: [], activeDocument: nil)

    init(
        documentStore: OpenDocumentsStore,
        documentRouter: WorkspaceDocumentRouting
    ) {
        self.documentStore = documentStore
        self.documentRouter = documentRouter
        super.init(nibName: nil, bundle: nil)
    }

    convenience init() {
        self.init(documentStore: .shared, documentRouter: WorkspaceDocumentCoordinator.shared)
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
        activeEditorCoordinator = ActiveEditorCoordinator(parentViewController: self, containerView: editorContainerView)
        configureActiveEditorCoordinator()
        configureStatusBar()
        configureTabBar()
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(sidebarView)
        view.addSubview(editorContainerView)
        view.addSubview(tabBarController.view)
        view.addSubview(statusBarView)
        view.addSubview(fontSizeHUDView)
        view.addSubview(resizeHandle)

        let widthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: sidebarResizer.storedWidth())
        sidebarWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            widthConstraint,

            tabBarController.view.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            tabBarController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarController.view.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarController.view.heightAnchor.constraint(equalToConstant: EditorTabBarLayout.tabBarHeight),

            editorContainerView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            editorContainerView.topAnchor.constraint(equalTo: tabBarController.view.bottomAnchor),
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
            resizeHandle.widthAnchor.constraint(equalToConstant: OpenFilesSidebarResizer.handleWidth),
        ])

        sidebarResizer.attach(to: resizeHandle, in: view, widthConstraint: widthConstraint)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        documentsObservation = documentStore.observe { [weak self] state in
            self?.documentState = state
            self?.syncWorkspace()
        }
        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.handleThemeDidChange()
        }
    }

    func increaseEditorFontSize() {
        activeEditorCoordinator?.increaseFontSize()
        showFontSizeHUD()
    }

    func decreaseEditorFontSize() {
        activeEditorCoordinator?.decreaseFontSize()
        showFontSizeHUD()
    }

    func focusActiveEditor() {
        activeEditorCoordinator?.focusEditor()
    }

    func toggleLineComment() {
        activeEditorCoordinator?.toggleLineComment()
    }

    func duplicateSelectedLines() {
        activeEditorCoordinator?.duplicateSelectedLines()
    }

    func deleteCurrentLine() {
        activeEditorCoordinator?.deleteCurrentLine()
    }

    @discardableResult
    func moveSelectedLinesUp() -> Bool {
        activeEditorCoordinator?.moveSelectedLinesUp() ?? false
    }

    @discardableResult
    func moveSelectedLinesDown() -> Bool {
        activeEditorCoordinator?.moveSelectedLinesDown() ?? false
    }

    func formatJSON() {
        activeEditorCoordinator?.formatJSON()
    }

    func currentLineNumber() -> Int {
        activeEditorCoordinator?.currentLineNumber() ?? 1
    }

    @discardableResult
    func goToLine(_ lineNumber: Int) -> Bool {
        activeEditorCoordinator?.goToLine(lineNumber) ?? false
    }

    private func configureTabBar() {
        tabBarController.onSelectDocument = { [weak self] document in
            self?.present(document)
        }
        tabBarController.onCloseDocument = { [weak self] document in
            self?.close(document)
        }
        tabBarController.onCloseOtherDocuments = { [weak self] document in
            self?.closeAll(except: document)
        }
        tabBarController.onCloseAllDocuments = { [weak self] in
            self?.closeAll()
        }
        tabBarController.onCreateNewDocument = { [weak self] in
            self?.createNewTabFromTabBar()
        }
    }

    private func configureActiveEditorCoordinator() {
        activeEditorCoordinator?.onOpenURLs = { [weak self] urls in
            self?.openFileSystemURLs(urls)
        }
        activeEditorCoordinator?.onCursorPositionChanged = { [weak self] in
            self?.updateStatusBar()
        }
    }

    private func createNewTabFromTabBar() {
        documentRouter.createUntitledDocument()
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

    private func handleDocumentsDidChange() {
        syncWorkspace()
    }

    private func handleThemeDidChange() {
        applyTheme()
        updateStatusBar()
    }

    private func applyTheme() {
        view.layer?.backgroundColor = AppColors.appBackground.cgColor
        editorContainerView.layer?.backgroundColor = AppColors.editorBackground.cgColor
        tabBarController.refreshTheme()
        statusBarView.applyTheme()
        fontSizeHUDView.applyTheme()
    }

    private func showFontSizeHUD() {
        guard activeEditorCoordinator?.hasActiveEditor == true else { return }
        fontSizeHUDView.show(fontSize: EditorSettings.currentFontSize())
    }

    private func syncWorkspace() {
        tabBarController.update(
            documents: documentState.documents,
            activeDocument: documentState.activeDocument
        )
        displayActiveDocumentIfNeeded()
    }

    private func present(_ document: Document) {
        documentRouter.present(document: document)
    }

    private func close(_ document: Document) {
        documentRouter.close(document: document)
    }

    private func closeAll(except documentToKeep: Document) {
        close(documentState.documents.filter { $0 !== documentToKeep })
    }

    private func closeAll() {
        close(documentState.documents)
    }

    private func close(_ documents: [Document]) {
        for document in documents {
            WorkspaceDocumentCoordinator.shared.close(document: document)
        }
    }

    private func displayActiveDocumentIfNeeded() {
        let activeDocument = documentState.activeDocument
        observeActiveDocumentSyntaxHighlighting(activeDocument)
        activeEditorCoordinator?.display(document: activeDocument)
        updateStatusBar()
    }

    private func observeActiveDocumentSyntaxHighlighting(_ document: Document?) {
        activeDocumentSyntaxObservation?.cancel()
        activeDocumentSyntaxObservation = document?.observeSyntaxHighlightingChanges { [weak self] _ in
            self?.updateStatusBar()
        }
    }

    private func updateStatusBar() {
        statusBarView.update(
            state: EditorStatusBarStateBuilder.makeState(
                document: documentState.activeDocument,
                cursorPosition: activeEditorCoordinator?.currentCursorPosition()
            )
        )
    }

    private func selectAutomaticSyntaxHighlighting() {
        documentState.activeDocument?.setSyntaxLanguageOverride(nil)
    }

    private func selectSyntaxHighlightingOverride(_ language: SyntaxLanguage) {
        documentState.activeDocument?.setSyntaxLanguageOverride(language)
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
