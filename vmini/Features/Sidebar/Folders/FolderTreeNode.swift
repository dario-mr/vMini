import AppKit

@MainActor
final class FolderTreeNode {
    let url: URL
    let title: String
    let isDirectory: Bool

    private var loadedChildren: [FolderTreeNode]?
    private weak var provider: FolderTreeProviding?

    init(url: URL, title: String, isDirectory: Bool, provider: FolderTreeProviding) {
        self.url = url
        self.title = title
        self.isDirectory = isDirectory
        self.provider = provider
    }

    var children: [FolderTreeNode] {
        if let loadedChildren {
            return loadedChildren
        }

        guard let provider else { return [] }
        let nodes = provider.childNodes(for: url)
        loadedChildren = nodes
        return nodes
    }

    func invalidateChildren() {
        loadedChildren = nil
    }
}
