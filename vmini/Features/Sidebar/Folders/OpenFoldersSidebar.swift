import AppKit

@MainActor
final class OpenFoldersSidebarViewController: NSViewController {
    private enum Constants {
        static let headerFontSize: CGFloat = 13
        static let sectionInset: CGFloat = 14
        static let headerTopInset: CGFloat = 4
        static let headerBottomInset: CGFloat = 3
        static let rowSpacing: CGFloat = 0
        static let indentationPerLevel: CGFloat = 14
    }

    var onFileSelected: ((URL) -> Void)? {
        didSet {
            outlineController.onFileSelected = onFileSelected
        }
    }

    var onFileDoubleClicked: ((URL) -> Void)? {
        didSet {
            outlineController.onFileDoubleClicked = onFileDoubleClicked
        }
    }

    private let headerContainer = NSView()
    private let headerLabel = NSTextField(labelWithString: "FOLDERS")
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let folderStore: OpenFoldersStore
    private let outlineController: OpenFoldersSidebarOutlineController
    private let folderWatcher = SidebarFolderWatcher()
    private var watchedDirectoryPaths: Set<String> = []
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

            headerLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: Constants.sectionInset),
            headerLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -Constants.sectionInset),
            headerLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: Constants.headerTopInset),
            headerLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -Constants.headerBottomInset),

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
        configureHeaderAppearance()
    }

    private func configureOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FoldersColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = OpenFoldersSidebarOutlineController.Constants.rowHeight
        outlineView.intercellSpacing = NSSize(width: 0, height: Constants.rowSpacing)
        outlineView.focusRingType = .none
        outlineView.backgroundColor = .clear
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .sourceList
        outlineView.indentationPerLevel = Constants.indentationPerLevel
        outlineController.attach(to: outlineView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.documentView = outlineView
    }

    private func applyTheme() {
        configureHeaderAppearance()
        outlineController.applyTheme()
    }

    private func updateFolderWatcher(for state: OpenFoldersStore.State) {
        let watchedPaths = Set(state.folderURLs.map(\.standardizedFileURL.path))
            .union(state.expandedFolderPaths)
        guard watchedPaths != watchedDirectoryPaths else { return }

        watchedDirectoryPaths = watchedPaths
        let watchedURLs = watchedPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        folderWatcher.watch(directoryURLs: watchedURLs) { [weak self] changedURLs in
            self?.folderStore.refreshContents(at: changedURLs)
        }
    }

    func setHidden(_ isHidden: Bool) {
        headerContainer.isHidden = isHidden
        scrollView.isHidden = isHidden

        if isHidden {
            NSLayoutConstraint.deactivate(expandedLayoutConstraints)
        } else {
            NSLayoutConstraint.activate(expandedLayoutConstraints)
        }
    }

    private func configureHeaderAppearance() {
        headerLabel.font = NSFont.systemFont(ofSize: Constants.headerFontSize, weight: .medium)
        headerLabel.textColor = AppColors.sidebarText
        headerLabel.alignment = .left
        headerLabel.drawsBackground = false
        headerLabel.backgroundColor = .clear
    }
}
