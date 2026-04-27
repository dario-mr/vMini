import AppKit

final class FolderTreeNode {
    let url: URL

    private var loadedChildren: [FolderTreeNode]?

    init(url: URL) {
        self.url = url
    }

    var title: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var isDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var children: [FolderTreeNode] {
        if let loadedChildren {
            return loadedChildren
        }

        let values: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .localizedNameKey]
        let childURLs = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: values,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        let nodes = childURLs
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map(FolderTreeNode.init(url:))
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        loadedChildren = nodes
        return nodes
    }
}

final class OpenFoldersSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private enum Constants {
        static let headerFontSize: CGFloat = 14
        static let rowFontSize: CGFloat = 13
        static let rowHeight: CGFloat = 23
    }

    var onFileSelected: ((URL) -> Void)?

    private let headerContainer = NSView()
    private let headerLabel = NSTextField(labelWithString: "FOLDERS")
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private var rootNodes: [FolderTreeNode] = []
    private var isApplyingExpansionState = false
    private var isApplyingSelection = false

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        configureHeaderContainer()
        configureHeaderLabel()
        configureOutlineView()

        view.addSubview(headerContainer)
        headerContainer.addSubview(headerLabel)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
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
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFolders),
            name: OpenFoldersStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExpansionStateChange),
            name: OpenFoldersStore.expansionDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applySelection),
            name: OpenFoldersStore.selectionDidChangeNotification,
            object: nil
        )

        reloadFolders()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        node(for: item)?.children.count ?? rootNodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(for: item)?.children[index] ?? rootNodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        node(for: item)?.isDirectory == true
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        Constants.rowHeight
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        SidebarSelectionRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = node(for: item) else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("FolderTreeCell")
        let cellView = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? makeCellView(identifier: identifier)

        cellView.imageView?.image = icon(for: node)
        cellView.textField?.stringValue = node.title
        cellView.textField?.font = NSFont.systemFont(ofSize: Constants.rowFontSize, weight: node.isDirectory ? .semibold : .regular)
        cellView.textField?.textColor = NSColor(white: 0.86, alpha: 1.0)
        return cellView
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        guard outlineView.selectedRow >= 0, let node = outlineView.item(atRow: outlineView.selectedRow) as? FolderTreeNode else { return }
        OpenFoldersStore.shared.select(node.url)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isApplyingExpansionState, let node = notification.userInfo?["NSObject"] as? FolderTreeNode else { return }
        OpenFoldersStore.shared.setExpanded(true, for: node.url)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isApplyingExpansionState, let node = notification.userInfo?["NSObject"] as? FolderTreeNode else { return }
        OpenFoldersStore.shared.setExpanded(false, for: node.url)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FolderTreeNode else { return }
        guard let folderURL = rootFolderURL(containing: node.url) else { return }

        let item = NSMenuItem(
            title: "Remove Folder",
            action: #selector(removeFolder(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = folderURL
        menu.addItem(item)
    }

    @objc
    private func activateSelectedItem() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FolderTreeNode else { return }

        OpenFoldersStore.shared.select(node.url)
        applySelection()

        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else {
            onFileSelected?(node.url)
        }
    }

    private func configureHeaderContainer() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureHeaderLabel() {
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.systemFont(ofSize: Constants.headerFontSize, weight: .semibold)
        headerLabel.textColor = NSColor(white: 0.84, alpha: 1.0)
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
        outlineView.rowHeight = Constants.rowHeight
        outlineView.intercellSpacing = NSSize(width: 0, height: 1)
        outlineView.focusRingType = .none
        outlineView.backgroundColor = .clear
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .sourceList
        outlineView.indentationPerLevel = 14
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.target = self
        outlineView.action = #selector(activateSelectedItem)

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.documentView = outlineView
    }

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cellView = NSTableCellView()
        cellView.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.font = NSFont.systemFont(ofSize: Constants.rowFontSize)

        cellView.imageView = imageView
        cellView.textField = textField
        cellView.addSubview(imageView)
        cellView.addSubview(textField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
            textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])

        return cellView
    }

    private func icon(for node: FolderTreeNode) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: node.url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func node(for item: Any?) -> FolderTreeNode? {
        item as? FolderTreeNode
    }

    private func rootFolderURL(containing url: URL) -> URL? {
        let path = url.standardizedFileURL.path
        return OpenFoldersStore.shared.folderURLs.first { rootURL in
            path == rootURL.path || path.hasPrefix(rootURL.path + "/")
        }
    }

    @objc
    private func reloadFolders() {
        rootNodes = OpenFoldersStore.shared.folderURLs.map(FolderTreeNode.init(url:))
        outlineView.reloadData()
        applyExpansionState()
        applySelection()
    }

    @objc
    private func handleExpansionStateChange() {
        applyExpansionState()
    }

    private func applyExpansionState() {
        guard isViewLoaded else { return }

        isApplyingExpansionState = true
        applyExpansionState(to: rootNodes)
        isApplyingExpansionState = false
        applySelection()
    }

    private func applyExpansionState(to nodes: [FolderTreeNode]) {
        for node in nodes where node.isDirectory {
            if OpenFoldersStore.shared.isExpanded(node.url) {
                outlineView.expandItem(node)
                applyExpansionState(to: node.children)
            } else {
                outlineView.collapseItem(node)
            }
        }
    }

    @objc
    private func removeFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        OpenFoldersStore.shared.remove(url)
    }

    @objc
    private func applySelection() {
        guard let selectedURL = OpenFoldersStore.shared.selectedURL,
              let node = visibleNode(matching: selectedURL, in: rootNodes) else {
            isApplyingSelection = true
            outlineView.deselectAll(nil)
            isApplyingSelection = false
            return
        }

        let row = outlineView.row(forItem: node)
        guard row >= 0 else {
            isApplyingSelection = true
            outlineView.deselectAll(nil)
            isApplyingSelection = false
            return
        }

        isApplyingSelection = true
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isApplyingSelection = false
    }

    private func visibleNode(matching url: URL, in nodes: [FolderTreeNode]) -> FolderTreeNode? {
        for node in nodes {
            if node.url.standardizedFileURL == url {
                return node
            }

            if outlineView.isItemExpanded(node), let child = visibleNode(matching: url, in: node.children) {
                return child
            }
        }

        return nil
    }
}
