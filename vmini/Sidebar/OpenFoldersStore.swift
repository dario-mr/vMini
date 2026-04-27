import AppKit

@MainActor
final class OpenFoldersStore {
    static let shared = OpenFoldersStore()
    static let didChangeNotification = Notification.Name("OpenFoldersStoreDidChange")
    static let expansionDidChangeNotification = Notification.Name("OpenFoldersStoreExpansionDidChange")
    static let selectionDidChangeNotification = Notification.Name("OpenFoldersStoreSelectionDidChange")

    private(set) var folderURLs: [URL] = []
    private(set) var selectedURL: URL?
    private var expandedFolderPaths: Set<String> = []
    private var isExpansionNotificationScheduled = false

    private init() {
        folderURLs = storedFolderURLs()
        expandedFolderPaths = Set(UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.openFoldersExpandedPaths) ?? [])
    }

    func add(_ urls: [URL]) {
        let directories = urls.filter { $0.hasDirectoryPath || isDirectory($0) }
        var didChange = false

        for url in directories {
            let standardizedURL = url.standardizedFileURL
            guard !folderURLs.contains(standardizedURL) else {
                continue
            }

            folderURLs.append(standardizedURL)
            expandedFolderPaths.insert(standardizedURL.path)
            didChange = true
        }

        if didChange {
            persist()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            scheduleExpansionDidChangeNotification()
        }
    }

    func remove(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard folderURLs.contains(standardizedURL) else { return }

        folderURLs.removeAll { $0 == standardizedURL }
        expandedFolderPaths = expandedFolderPaths.filter {
            $0 != standardizedURL.path && !$0.hasPrefix(standardizedURL.path + "/")
        }
        if let selectedPath = selectedURL?.path,
           selectedPath == standardizedURL.path || selectedPath.hasPrefix(standardizedURL.path + "/") {
            selectedURL = nil
            NotificationCenter.default.post(name: Self.selectionDidChangeNotification, object: nil)
        }
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        scheduleExpansionDidChangeNotification()
    }

    func setExpanded(_ isExpanded: Bool, for url: URL) {
        let path = url.standardizedFileURL.path
        let didChange: Bool

        if isExpanded {
            didChange = expandedFolderPaths.insert(path).inserted
        } else {
            didChange = expandedFolderPaths.remove(path) != nil
        }

        guard didChange else { return }

        UserDefaults.standard.set(Array(expandedFolderPaths), forKey: UserDefaultsKeys.openFoldersExpandedPaths)
        scheduleExpansionDidChangeNotification()
    }

    func isExpanded(_ url: URL) -> Bool {
        expandedFolderPaths.contains(url.standardizedFileURL.path)
    }

    func select(_ url: URL?) {
        let standardizedURL = url?.standardizedFileURL
        guard selectedURL != standardizedURL else { return }

        selectedURL = standardizedURL
        NotificationCenter.default.post(name: Self.selectionDidChangeNotification, object: nil)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func persist() {
        UserDefaults.standard.set(folderURLs.compactMap(bookmarkData), forKey: UserDefaultsKeys.openFolders)
        UserDefaults.standard.set(Array(expandedFolderPaths), forKey: UserDefaultsKeys.openFoldersExpandedPaths)
    }

    private func scheduleExpansionDidChangeNotification() {
        guard !isExpansionNotificationScheduled else { return }

        isExpansionNotificationScheduled = true
        Task { @MainActor in
            isExpansionNotificationScheduled = false
            NotificationCenter.default.post(name: Self.expansionDidChangeNotification, object: nil)
        }
    }

    private func storedFolderURLs() -> [URL] {
        guard let bookmarks = UserDefaults.standard.array(forKey: UserDefaultsKeys.openFolders) as? [Data] else {
            return []
        }

        return bookmarks.compactMap(resolveURL)
    }

    private func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolveURL(from data: Data) -> URL? {
        var isStale = false

        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ),
        !isStale,
        isDirectory(url) else {
            return nil
        }

        return url.standardizedFileURL
    }
}
