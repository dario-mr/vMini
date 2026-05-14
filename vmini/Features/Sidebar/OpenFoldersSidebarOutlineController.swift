import AppKit

@MainActor
final class OpenFoldersSidebarOutlineController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    enum Constants {
        static let rowFontSize: CGFloat = 13
        static let rowHeight: CGFloat = rowFontSize * 2
        static let rootFolderRowHeight: CGFloat = 32
    }

    var onFileSelected: ((URL) -> Void)?

    private let folderStore: OpenFoldersStore
    private let treeProvider: FolderTreeProvider
    private weak var outlineView: NSOutlineView?
    private var rootNodes: [FolderTreeNode] = []
    private var isApplyingExpansionState = false
    private var isApplyingSelection = false
    private var observedState: OpenFoldersStore.State?
    private lazy var expansionController = FolderSidebarExpansionController(outlineView: outlineView!, store: folderStore)
    private lazy var selectionController = FolderSidebarSelectionController(outlineView: outlineView!, store: folderStore)

    init(folderStore: OpenFoldersStore, treeProvider: FolderTreeProvider) {
        self.folderStore = folderStore
        self.treeProvider = treeProvider
    }

    func attach(to outlineView: NSOutlineView) {
        self.outlineView = outlineView
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.target = self
        outlineView.action = #selector(activateSelectedItem)

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu
    }

    func apply(state: OpenFoldersStore.State) {
        let previousState = observedState
        observedState = state

        if previousState?.folderURLs != state.folderURLs {
            reloadFolders()
            return
        }

        if previousState?.expandedFolderPaths != state.expandedFolderPaths {
            applyExpansionState()
        }

        if previousState?.selectedURL != state.selectedURL {
            applySelection()
        }
    }

    func applyTheme() {
        outlineView?.reloadData()
        outlineView?.needsDisplay = true
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
        if let node = node(for: item), rootNodes.contains(where: { $0 === node }) {
            return Constants.rootFolderRowHeight
        }

        return Constants.rowHeight
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
        cellView.textField?.textColor = AppColors.folderSidebarText
        return cellView
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        guard let outlineView, outlineView.selectedRow >= 0, let node = outlineView.item(atRow: outlineView.selectedRow) as? FolderTreeNode else { return }
        folderStore.select(node.url)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isApplyingExpansionState, let node = notification.userInfo?["NSObject"] as? FolderTreeNode else { return }
        folderStore.setExpanded(true, for: node.url)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isApplyingExpansionState, let node = notification.userInfo?["NSObject"] as? FolderTreeNode else { return }
        folderStore.setExpanded(false, for: node.url)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard let outlineView else { return }
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FolderTreeNode else { return }
        guard isRootNode(node) else { return }

        let item = NSMenuItem(title: "Remove Folder", action: #selector(removeFolder(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = node.url
        menu.addItem(item)
    }

    @objc
    private func activateSelectedItem() {
        guard let outlineView else { return }

        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FolderTreeNode else { return }

        folderStore.select(node.url)
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

    @objc
    private func removeFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        folderStore.remove(url)
    }

    private func reloadFolders() {
        guard let outlineView else { return }

        rootNodes = treeProvider.rootNodes(for: folderStore.folderURLs)
        outlineView.reloadData()
        applyExpansionState()
        applySelection()
    }

    private func applyExpansionState() {
        guard outlineView != nil else { return }

        isApplyingExpansionState = true
        expansionController.applyExpansionState(to: rootNodes)
        isApplyingExpansionState = false
        applySelection()
    }

    private func applySelection() {
        isApplyingSelection = true
        selectionController.applySelection(in: rootNodes)
        isApplyingSelection = false
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

    private func isRootNode(_ node: FolderTreeNode) -> Bool {
        rootNodes.contains { $0 === node }
    }
}
