import AppKit

final class FolderTreeNode {
    let url: URL

    private var loadedChildren: [FolderTreeNode]?
    private let provider: FolderTreeProviding

    init(url: URL, provider: FolderTreeProviding) {
        self.url = url
        self.provider = provider
    }

    var title: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var isDirectory: Bool {
        provider.isDirectory(url)
    }

    var children: [FolderTreeNode] {
        if let loadedChildren {
            return loadedChildren
        }

        let nodes = provider.childNodes(for: url)
        loadedChildren = nodes
        return nodes
    }
}
