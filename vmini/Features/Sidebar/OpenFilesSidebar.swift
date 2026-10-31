import AppKit

@MainActor
final class OpenFilesSidebarViewController: NSViewController {
    private enum Constants {
        static let headerFontSize: CGFloat = 13
        static let sectionInset: CGFloat = 14
        static let headerTopInset: CGFloat = 10
        static let headerBottomInset: CGFloat = 3
        static let separatorTopSpacing: CGFloat = 8
        static let separatorBottomSpacing: CGFloat = 8
        static let dividerThickness: CGFloat = 1
        static let rowSpacing: CGFloat = 1
        static let preferredFoldersHeight: CGFloat = 160
    }

    private let foldersViewController = OpenFoldersSidebarViewController()
    private let headerContainer = NSView()
    private let headerLabel = NSTextField(labelWithString: "OPEN FILES")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let dividerView = NSBox()
    private let documentStore: OpenDocumentsStore
    private let folderStore: OpenFoldersStore
    private let tableController: OpenFilesSidebarTableController
    private var openFilesHeightConstraint: NSLayoutConstraint?
    private var dividerTopConstraint: NSLayoutConstraint?
    private var dividerHeightConstraint: NSLayoutConstraint?
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
            documentRouter.preview(url: url)
        }
        foldersViewController.onFileDoubleClicked = { url in
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
        let dividerTopConstraint = dividerView.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: Constants.separatorTopSpacing)
        let dividerHeightConstraint = dividerView.heightAnchor.constraint(equalToConstant: Constants.dividerThickness)
        let foldersTopConstraint = foldersView.topAnchor.constraint(equalTo: dividerView.bottomAnchor, constant: Constants.separatorBottomSpacing)
        let foldersBottomConstraint = foldersView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let foldersHiddenHeightConstraint = foldersView.heightAnchor.constraint(equalToConstant: 0)
        self.openFilesHeightConstraint = openFilesHeightConstraint
        self.dividerTopConstraint = dividerTopConstraint
        self.dividerHeightConstraint = dividerHeightConstraint
        self.foldersTopConstraint = foldersTopConstraint
        self.foldersBottomConstraint = foldersBottomConstraint
        self.foldersHiddenHeightConstraint = foldersHiddenHeightConstraint

        view.addSubview(headerContainer)
        headerContainer.addSubview(headerLabel)
        view.addSubview(scrollView)
        view.addSubview(dividerView)
        view.addSubview(foldersView)

        NSLayoutConstraint.activate([
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.topAnchor.constraint(equalTo: view.topAnchor),

            headerLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: Constants.sectionInset),
            headerLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -Constants.sectionInset),
            headerLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: Constants.headerTopInset),
            headerLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -Constants.headerBottomInset),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            openFilesHeightConstraint,

            dividerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.sectionInset),
            dividerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.sectionInset),
            dividerTopConstraint,
            dividerHeightConstraint,

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

    }

    private func configureHeader() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.systemFont(ofSize: Constants.headerFontSize, weight: .medium)
        headerLabel.textColor = AppColors.sidebarText
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
        tableView.intercellSpacing = NSSize(width: 0, height: Constants.rowSpacing)
        tableView.focusRingType = .none
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .sourceList
        tableView.usesAlternatingRowBackgroundColors = false
        tableController.attach(to: tableView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.boxType = .separator
        scrollView.documentView = tableView
    }

    private func applyDocumentState(_ state: OpenDocumentsStore.State) {
        tableController.update(documents: state.documents, activeDocument: state.activeDocument)
        updateOpenFilesHeight()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateOpenFilesHeight()
    }

    private func updateOpenFilesHeight() {
        let contentHeight = tableController.contentHeight
        let availableHeight = max(0, view.bounds.height - headerContainer.frame.height)
        let reservedFoldersHeight = folderStore.folderURLs.isEmpty
            ? 0
            : Constants.preferredFoldersHeight
                + Constants.separatorTopSpacing
                + Constants.separatorBottomSpacing
                + Constants.dividerThickness
        let maxHeight = max(availableHeight / 2, availableHeight - reservedFoldersHeight)
        let height = min(contentHeight, maxHeight)
        if openFilesHeightConstraint?.constant != height {
            openFilesHeightConstraint?.constant = height
        }
        scrollView.hasVerticalScroller = contentHeight > height
        tableView.frame.size.height = contentHeight
    }

    @objc
    private func updateFoldersVisibility() {
        let hasFolders = !folderStore.folderURLs.isEmpty
        foldersViewController.setHidden(!hasFolders)
        foldersViewController.view.isHidden = !hasFolders
        dividerView.isHidden = !hasFolders
        dividerTopConstraint?.constant = hasFolders ? Constants.separatorTopSpacing : 0
        dividerHeightConstraint?.constant = hasFolders ? Constants.dividerThickness : 0
        foldersTopConstraint?.constant = hasFolders ? Constants.separatorBottomSpacing : 0
        foldersBottomConstraint?.isActive = hasFolders
        foldersHiddenHeightConstraint?.isActive = !hasFolders
        updateOpenFilesHeight()
    }

    private func applyTheme() {
        configureHeader()
        tableController.reload()
    }
}
