import AppKit

@MainActor
final class OpenFoldersSidebarViewController: NSViewController {
    private enum Constants {
        static let headerFontSize: CGFloat = 14
    }

    var onFileSelected: ((URL) -> Void)? {
        didSet {
            outlineController.onFileSelected = onFileSelected
        }
    }

    private let headerContainer = NSView()
    private let headerLabel = NSTextField(labelWithString: "FOLDERS")
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let folderStore: OpenFoldersStore
    private let outlineController: OpenFoldersSidebarOutlineController
    private let folderWatcher = SidebarFolderWatcher()
    private var expandedLayoutConstraints: [NSLayoutConstraint] = []
    private var foldersObservation: ObservationToken?
    private var themeObservation: ObservationToken?

    init(folderStore: OpenFoldersStore, treeProvider: FolderTreeProvider) {
        self.folderStore = folderStore
        self.outlineController = OpenFoldersSidebarOutlineController(folderStore: folderStore, treeProvider: treeProvider)
        super.init(nibName: nil, bundle: nil)
    }

    convenience init() {
        self.init(folderStore: .shared, treeProvider: FolderTreeProvider())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        configureHeader()
        configureOutlineView()

        view.addSubview(headerContainer)
        headerContainer.addSubview(headerLabel)
        view.addSubview(scrollView)

        expandedLayoutConstraints = [
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.topAnchor.constraint(equalTo: view.topAnchor),

            headerLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 14),
            headerLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -14),
            headerLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 12),
            headerLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -8),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]

        NSLayoutConstraint.activate(expandedLayoutConstraints)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        foldersObservation = folderStore.observe { [weak self] state in
            guard let self else { return }
            self.outlineController.apply(state: state)
            self.updateFolderWatcher(for: state)
        }
        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.applyTheme()
        }
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

    private func configureOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FoldersColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = OpenFoldersSidebarOutlineController.Constants.rowHeight
        outlineView.intercellSpacing = NSSize(width: 0, height: 1)
        outlineView.focusRingType = .none
        outlineView.backgroundColor = .clear
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .sourceList
        outlineView.indentationPerLevel = 14
        outlineController.attach(to: outlineView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.documentView = outlineView
    }

    private func applyTheme() {
        headerLabel.textColor = AppColors.sidebarHeaderText
        outlineController.applyTheme()
    }

    private func updateFolderWatcher(for state: OpenFoldersStore.State) {
        let watchedURLs = state.folderURLs + state.expandedFolderPaths.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        folderWatcher.watch(directoryURLs: watchedURLs) { [weak self] in
            self?.folderStore.refreshContents()
        }
    }

    func setCollapsed(_ isCollapsed: Bool) {
        headerContainer.isHidden = isCollapsed
        scrollView.isHidden = isCollapsed

        if isCollapsed {
            NSLayoutConstraint.deactivate(expandedLayoutConstraints)
        } else {
            NSLayoutConstraint.activate(expandedLayoutConstraints)
        }
    }
}
