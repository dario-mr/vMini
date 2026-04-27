import AppKit

private final class NonScrollingClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin = .zero
        return bounds
    }
}

final class OpenFilesSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Constants {
        static let headerFontSize: CGFloat = 14
        static let rowFontSize: CGFloat = 14
        static let rowHeight: CGFloat = 28
    }

    private weak var initialDocument: Document?
    private let foldersViewController = OpenFoldersSidebarViewController()
    private let headerContainer = NSView()
    private let headerLabel = NSTextField(labelWithString: "OPEN FILES")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var openFilesHeightConstraint: NSLayoutConstraint?
    private var foldersTopConstraint: NSLayoutConstraint?
    private var foldersBottomConstraint: NSLayoutConstraint?
    private var foldersHiddenHeightConstraint: NSLayoutConstraint?
    private var isReloadingSelection = false

    init(initialDocument: Document) {
        self.initialDocument = initialDocument
        super.init(nibName: nil, bundle: nil)
        foldersViewController.onFileSelected = { [weak self] url in
            guard let window = self?.view.window else { return }
            OpenURLRouter.open([url], tabbedIn: window)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var documents: [Document] {
        OpenDocumentsStore.shared.documents
    }

    private var owningDocument: Document? {
        if let document = view.window?.windowController?.document as? Document {
            return document
        }

        return initialDocument
    }

    override func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        view = visualEffectView
        view.translatesAutoresizingMaskIntoConstraints = false
        addChild(foldersViewController)

        configureHeaderContainer()
        configureHeaderLabel()
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadDocuments),
            name: OpenDocumentsStore.didChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateFoldersVisibility),
            name: OpenFoldersStore.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reloadDocuments()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        documents.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Constants.rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarSelectionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("OpenFileCell")
        let cellView = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? makeCellView(identifier: identifier)
        let document = documents[row]
        let isEdited = document.isDocumentEdited
        cellView.textField?.attributedStringValue = attributedTitle(
            for: document,
            isEdited: isEdited
        )
        cellView.textField?.font = NSFont.systemFont(ofSize: Constants.rowFontSize, weight: .medium)
        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloadingSelection else {
            return
        }
    }

    @objc
    private func reloadDocuments() {
        isReloadingSelection = true
        tableView.reloadData()
        updateOpenFilesHeight()

        guard let currentDocument = owningDocument else {
            tableView.deselectAll(nil)
            isReloadingSelection = false
            return
        }

        if let row = documents.firstIndex(where: { $0 === currentDocument }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }

        isReloadingSelection = false
    }

    private func configureHeaderLabel() {
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.systemFont(ofSize: Constants.headerFontSize, weight: .semibold)
        headerLabel.textColor = NSColor(white: 0.84, alpha: 1.0)
        headerLabel.alignment = .left
        headerLabel.drawsBackground = false
        headerLabel.backgroundColor = .clear
    }

    private func configureHeaderContainer() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OpenFilesColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .default
        tableView.rowHeight = Constants.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.focusRingType = .none
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .sourceList
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(activateSelection)
        tableView.doubleAction = #selector(activateSelection)

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

    private func updateOpenFilesHeight() {
        let height: CGFloat
        if documents.isEmpty {
            height = 0
        } else {
            height = tableView.rect(ofRow: documents.count - 1).maxY
        }

        openFilesHeightConstraint?.constant = height
        tableView.frame.size.height = height
        scrollView.contentView.scroll(to: .zero)
    }

    @objc
    private func updateFoldersVisibility() {
        let hasFolders = !OpenFoldersStore.shared.folderURLs.isEmpty
        foldersViewController.view.isHidden = !hasFolders
        foldersTopConstraint?.constant = hasFolders ? 8 : 0
        foldersBottomConstraint?.isActive = hasFolders
        foldersHiddenHeightConstraint?.isActive = !hasFolders
    }

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cellView = NSTableCellView()
        cellView.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.textColor = NSColor(white: 0.88, alpha: 1.0)
        textField.font = NSFont.systemFont(ofSize: Constants.rowFontSize, weight: .medium)

        cellView.textField = textField
        cellView.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -12),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])

        return cellView
    }

    private func attributedTitle(for document: Document, isEdited: Bool) -> NSAttributedString {
        let title = isEdited ? "• \(document.sidebarTitle)" : document.sidebarTitle
        return NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: Constants.rowFontSize, weight: .medium),
                .foregroundColor: NSColor(white: 0.88, alpha: 1.0),
            ]
        )
    }

    @objc
    private func activateSelection() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < documents.count else { return }

        let document = documents[row]
        guard let windowController = document.windowControllers.first, let window = windowController.window else {
            return
        }

        window.makeKeyAndOrderFront(nil)
    }

    @objc
    private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === view.window else {
            return
        }

        reloadDocuments()
    }
}
