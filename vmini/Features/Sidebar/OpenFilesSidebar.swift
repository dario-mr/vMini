import AppKit

private final class NonScrollingClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin = .zero
        return bounds
    }
}

@MainActor
final class OpenFilesSidebarViewController: NSViewController {
    private enum Constants {
        static let headerFontSize: CGFloat = 14
    }

    private let foldersViewController = OpenFoldersSidebarViewController()
    private let headerContainer = NSView()
    private let headerLabel = NSTextField(labelWithString: "OPEN FILES")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let documentStore: OpenDocumentsStore
    private let folderStore: OpenFoldersStore
    private let tableController: OpenFilesSidebarTableController
    private var openFilesHeightConstraint: NSLayoutConstraint?
    private var foldersTopConstraint: NSLayoutConstraint?
    private var foldersBottomConstraint: NSLayoutConstraint?
    private var foldersHiddenHeightConstraint: NSLayoutConstraint?
    private var documentsObservation: ObservationToken?
    private var foldersObservation: ObservationToken?
    private var themeObservation: ObservationToken?

    init(
        documentStore: OpenDocumentsStore,
        folderStore: OpenFoldersStore,
        documentRouter: WorkspaceDocumentRouting
    ) {
        self.documentStore = documentStore
        self.folderStore = folderStore
        self.tableController = OpenFilesSidebarTableController(documentRouter: documentRouter)
        super.init(nibName: nil, bundle: nil)
        foldersViewController.onFileSelected = { url in
            documentRouter.open(urls: [url], activate: url)
        }
    }

    convenience init() {
        self.init(
            documentStore: .shared,
            folderStore: .shared,
            documentRouter: WorkspaceDocumentCoordinator.shared
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        view = visualEffectView
        view.translatesAutoresizingMaskIntoConstraints = false
        addChild(foldersViewController)

        configureHeader()
        configureTableView()

        let foldersView = foldersViewController.view
        foldersView.translatesAutoresizingMaskIntoConstraints = false

        let openFilesHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)
        let foldersTopConstraint = foldersView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8)
        let foldersBottomConstraint = foldersView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let foldersHiddenHeightConstraint = foldersView.heightAnchor.constraint(equalToConstant: 0)
        self.openFilesHeightConstraint = openFilesHeightConstraint
        self.foldersTopConstraint = foldersTopConstraint
        self.foldersBottomConstraint = foldersBottomConstraint
        self.foldersHiddenHeightConstraint = foldersHiddenHeightConstraint

        view.addSubview(headerContainer)
        headerContainer.addSubview(headerLabel)
        view.addSubview(scrollView)
        view.addSubview(foldersView)

        NSLayoutConstraint.activate([
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.topAnchor.constraint(equalTo: view.topAnchor),

            headerLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 14),
            headerLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -14),
            headerLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 14),
            headerLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -10),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            openFilesHeightConstraint,

            foldersView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            foldersView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            foldersTopConstraint,
        ])

        updateFoldersVisibility()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        documentsObservation = documentStore.observe { [weak self] state in
            self?.applyDocumentState(state)
        }
        foldersObservation = folderStore.observe { [weak self] _ in
            self?.updateFoldersVisibility()
        }
        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.applyTheme()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureHeader() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.systemFont(ofSize: Constants.headerFontSize, weight: .semibold)
        headerLabel.textColor = AppColors.sidebarHeaderText
        headerLabel.alignment = .left
        headerLabel.drawsBackground = false
        headerLabel.backgroundColor = .clear
    }

    private func configureTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OpenFilesColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .default
        tableView.rowHeight = OpenFilesSidebarTableController.Constants.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.focusRingType = .none
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .sourceList
        tableView.usesAlternatingRowBackgroundColors = false
        tableController.attach(to: tableView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = NonScrollingClipView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.documentView = tableView
    }

    private func applyDocumentState(_ state: OpenDocumentsStore.State) {
        tableController.update(documents: state.documents, activeDocument: state.activeDocument)
        updateOpenFilesHeight()
    }

    private func updateOpenFilesHeight() {
        let height = tableController.contentHeight
        openFilesHeightConstraint?.constant = height
        tableView.frame.size.height = height
        scrollView.contentView.scroll(to: .zero)
    }

    @objc
    private func updateFoldersVisibility() {
        let hasFolders = !folderStore.folderURLs.isEmpty
        foldersViewController.setCollapsed(!hasFolders)
        foldersViewController.view.isHidden = !hasFolders
        foldersTopConstraint?.constant = hasFolders ? 8 : 0
        foldersBottomConstraint?.isActive = hasFolders
        foldersHiddenHeightConstraint?.isActive = !hasFolders
    }

    @objc
    private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === view.window else {
            return
        }

        tableController.reload()
    }

    private func applyTheme() {
        headerLabel.textColor = AppColors.sidebarHeaderText
        tableController.applyTheme()
        tableController.reload()
    }
}
