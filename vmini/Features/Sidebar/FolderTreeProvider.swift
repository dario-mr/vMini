import AppKit

protocol FolderTreeProviding: AnyObject {
    func childNodes(for url: URL) -> [FolderTreeNode]
}

final class FolderTreeProvider: FolderTreeProviding {
    private struct NodeMetadata {
        let title: String
        let isDirectory: Bool
    }

    private let fileManager: FileManager
    private var nodesByPath: [String: FolderTreeNode] = [:]
    private var childURLsByPath: [String: [URL]] = [:]
    private var metadataByPath: [String: NodeMetadata] = [:]

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    convenience init() {
        self.init(fileManager: .default)
    }

    func rootNodes(for urls: [URL]) -> [FolderTreeNode] {
        urls.map { node(for: $0, metadata: metadata(for: $0)) }
    }

    func childNodes(for url: URL) -> [FolderTreeNode] {
        let standardizedPath = url.standardizedFileURL.path
        let childURLs = childURLsByPath[standardizedPath] ?? loadChildURLs(for: url)
        childURLsByPath[standardizedPath] = childURLs

        return childURLs
            .map { childURL in
                node(for: childURL, metadata: metadata(for: childURL))
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func invalidateContents(at urls: [URL]) {
        let invalidatedPaths = Set(urls.map(\.standardizedFileURL.path))
        guard !invalidatedPaths.isEmpty else { return }

        for path in invalidatedPaths {
            childURLsByPath.removeValue(forKey: path)
            nodesByPath[path]?.invalidateChildren()
        }

        let descendantPaths = reachablePaths(from: invalidatedPaths).subtracting(invalidatedPaths)
        nodesByPath = nodesByPath.filter { !descendantPaths.contains($0.key) }
        metadataByPath = metadataByPath.filter { !descendantPaths.contains($0.key) }
    }

    private func loadChildURLs(for url: URL) -> [URL] {
        let values: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let childURLs = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: values,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        return childURLs
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map(\.standardizedFileURL)
    }

    private func metadata(for url: URL) -> NodeMetadata {
        let standardizedPath = url.standardizedFileURL.path
        if let cachedMetadata = metadataByPath[standardizedPath] {
            return cachedMetadata
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let metadata = NodeMetadata(
            title: fallbackTitle(for: url),
            isDirectory: resourceValues?.isDirectory ?? false
        )
        metadataByPath[standardizedPath] = metadata
        return metadata
    }

    private func node(for url: URL, metadata: NodeMetadata) -> FolderTreeNode {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path
        if let existingNode = nodesByPath[path] {
            return existingNode
        }

        let node = FolderTreeNode(
            url: standardizedURL,
            title: metadata.title,
            isDirectory: metadata.isDirectory,
            provider: self
        )
        nodesByPath[path] = node
        return node
    }

    private func reachablePaths(from roots: Set<String>) -> Set<String> {
        var reachable = roots
        var pending = Array(roots)

        while let path = pending.popLast() {
            guard let childURLs = childURLsByPath[path] else { continue }

            for childURL in childURLs {
                let childPath = childURL.standardizedFileURL.path
                if reachable.insert(childPath).inserted {
                    pending.append(childPath)
                }
            }
        }

        return reachable
    }

    private func fallbackTitle(for url: URL) -> String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }
}
