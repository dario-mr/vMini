import AppKit

protocol FolderTreeProviding: AnyObject {
    func isDirectory(_ url: URL) -> Bool
    func childNodes(for url: URL) -> [FolderTreeNode]
}

final class FolderTreeProvider: FolderTreeProviding {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    convenience init() {
        self.init(fileManager: .default)
    }

    func rootNodes(for urls: [URL]) -> [FolderTreeNode] {
        urls.map { FolderTreeNode(url: $0, provider: self) }
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func childNodes(for url: URL) -> [FolderTreeNode] {
        let values: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .localizedNameKey]
        let childURLs = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: values,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        return childURLs
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { FolderTreeNode(url: $0, provider: self) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }
}
