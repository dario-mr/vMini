import AppKit

@MainActor
final class FolderSidebarSelectionController {
    private let outlineView: NSOutlineView
    private let store: OpenFoldersStore

    init(outlineView: NSOutlineView, store: OpenFoldersStore) {
        self.outlineView = outlineView
        self.store = store
    }

    func applySelection(in rootNodes: [FolderTreeNode]) {
        guard let selectedURL = store.selectedURL,
              let node = visibleNode(matching: selectedURL, in: rootNodes) else {
            outlineView.deselectAll(nil)
            return
        }

        let row = outlineView.row(forItem: node)
        guard row >= 0 else {
            outlineView.deselectAll(nil)
            return
        }

        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
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
