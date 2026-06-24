import AppKit

final class FolderTreeNode {
    let url: URL
    let title: String
    let isDirectory: Bool

    private var loadedChildren: [FolderTreeNode]?
    private let provider: FolderTreeProviding

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

        let nodes = provider.childNodes(for: url)
        loadedChildren = nodes
        return nodes
    }

    func invalidateChildren() {
        loadedChildren = nil
    }
}
