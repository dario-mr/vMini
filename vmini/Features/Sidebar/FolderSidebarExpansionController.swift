import AppKit

@MainActor
final class FolderSidebarExpansionController {
    private let outlineView: NSOutlineView
    private let store: OpenFoldersStore

    init(outlineView: NSOutlineView, store: OpenFoldersStore) {
        self.outlineView = outlineView
        self.store = store
    }

    func applyExpansionState(to nodes: [FolderTreeNode]) {
        for node in nodes where node.isDirectory {
            if store.isExpanded(node.url) {
                if !outlineView.isItemExpanded(node) {
                    outlineView.expandItem(node)
                }
                applyExpansionState(to: node.children)
            } else if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            }
        }
    }
}
