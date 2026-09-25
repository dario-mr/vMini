import AppKit

@MainActor
protocol FolderTreeProviding: AnyObject {
    func childNodes(for url: URL) -> [FolderTreeNode]
}

private struct FolderChildSnapshot: Sendable {
    struct Child: Sendable {
        let url: URL
        let title: String
        let isDirectory: Bool
    }

    let children: [Child]

    static func load(for url: URL) -> FolderChildSnapshot {
        let values: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: values,
            options: [.skipsPackageDescendants]
        )) ?? []

        return FolderChildSnapshot(children: urls
            .filter { $0.lastPathComponent != ".DS_Store" }
            .map { childURL in
                let standardizedURL = childURL.standardizedFileURL
                let isDirectory = (try? standardizedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return Child(
                    url: standardizedURL,
                    title: standardizedURL.lastPathComponent,
                    isDirectory: isDirectory
                )
            })
    }
}

@MainActor
final class FolderTreeProvider: FolderTreeProviding {
    private struct NodeMetadata {
        let title: String
        let isDirectory: Bool
    }

    private struct PendingLoad {
        let id: UUID
        let task: Task<FolderChildSnapshot, Never>
    }

    var onChildrenLoaded: ((URL) -> Void)?

    private var nodesByPath: [String: FolderTreeNode] = [:]
    private var childURLsByPath: [String: [URL]] = [:]
    private var metadataByPath: [String: NodeMetadata] = [:]
    private var pendingChildLoads: [String: PendingLoad] = [:]

    init() {}

    func rootNodes(for urls: [URL]) -> [FolderTreeNode] {
        urls.map { node(for: $0, metadata: metadata(for: $0)) }
    }

    func childNodes(for url: URL) -> [FolderTreeNode] {
        let path = url.standardizedFileURL.path
        guard let childURLs = childURLsByPath[path] else {
            startLoadingChildren(for: url)
            return []
        }

        return childURLs
            .map { childURL in
                node(for: childURL, metadata: metadataByPath[childURL.path] ?? metadata(for: childURL))
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func loadChildren(for url: URL) async {
        let path = url.standardizedFileURL.path
        guard childURLsByPath[path] == nil else { return }

        let pending: PendingLoad
        if let existing = pendingChildLoads[path] {
            pending = existing
        } else {
            pending = makePendingLoad(for: url)
            pendingChildLoads[path] = pending
        }
        await apply(pending, for: url)
    }

    @discardableResult
    func invalidateContents(at urls: [URL], removingRoots: Bool = false) -> Set<String> {
        let invalidatedPaths = Set(urls.map(\.standardizedFileURL.path))
        guard !invalidatedPaths.isEmpty else { return [] }

        let affectedPaths = reachablePaths(from: invalidatedPaths)
        for path in affectedPaths {
            nodesByPath[path]?.invalidateChildren()
            // The outline still holds refreshed directories; evict only their descendants.
            if removingRoots || !invalidatedPaths.contains(path) {
                nodesByPath.removeValue(forKey: path)
            }
            childURLsByPath.removeValue(forKey: path)
            metadataByPath.removeValue(forKey: path)
            pendingChildLoads.removeValue(forKey: path)?.task.cancel()
        }

        return affectedPaths
    }

    private func startLoadingChildren(for url: URL) {
        let path = url.standardizedFileURL.path
        guard pendingChildLoads[path] == nil else { return }
        let pending = makePendingLoad(for: url)
        pendingChildLoads[path] = pending
        Task { [weak self] in
            await self?.apply(pending, for: url)
        }
    }

    private func makePendingLoad(for url: URL) -> PendingLoad {
        PendingLoad(
            id: UUID(),
            task: Task.detached(priority: .utility) {
                FolderChildSnapshot.load(for: url.standardizedFileURL)
            }
        )
    }

    private func apply(_ pending: PendingLoad, for url: URL) async {
        let path = url.standardizedFileURL.path
        let interval = AppPerformanceProfiler.beginInterval("SidebarChildrenLoad")
        defer { AppPerformanceProfiler.endInterval("SidebarChildrenLoad", interval) }

        let snapshot = await pending.task.value
        guard pendingChildLoads[path]?.id == pending.id else { return }

        pendingChildLoads.removeValue(forKey: path)
        let children = snapshot.children
        childURLsByPath[path] = children.map(\.url)
        for child in children {
            metadataByPath[child.url.path] = NodeMetadata(title: child.title, isDirectory: child.isDirectory)
        }
        nodesByPath[path]?.invalidateChildren()
        onChildrenLoaded?(url.standardizedFileURL)
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
