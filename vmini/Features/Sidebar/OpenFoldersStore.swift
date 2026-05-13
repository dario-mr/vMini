import AppKit

@MainActor
final class OpenFoldersStore {
    struct State: Equatable {
        let folderURLs: [URL]
        let selectedURL: URL?
        let expandedFolderPaths: Set<String>
    }

    static let shared = OpenFoldersStore()

    private let persistence: WorkspacePersistence
    private(set) var folderURLs: [URL] = []
    private(set) var selectedURL: URL?
    private var expandedFolderPaths: Set<String> = []
    private var observers: [UUID: (State) -> Void] = [:]
    private var isObserverNotificationScheduled = false

    init(persistence: WorkspacePersistence) {
        self.persistence = persistence
        folderURLs = storedFolderURLs()
        expandedFolderPaths = Set(persistence.openFolderExpandedPaths)
    }

    private convenience init() {
        self.init(persistence: .shared)
    }

    func observe(_ observer: @escaping (State) -> Void) -> ObservationToken {
        let identifier = UUID()
        observers[identifier] = observer
        observer(currentState())
        return ObservationToken { [weak self] in
            self?.observers.removeValue(forKey: identifier)
        }
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
            scheduleObserverNotification()
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
        }
        persist()
        scheduleObserverNotification()
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

        persistence.openFolderExpandedPaths = Array(expandedFolderPaths)
        scheduleObserverNotification()
    }

    func isExpanded(_ url: URL) -> Bool {
        expandedFolderPaths.contains(url.standardizedFileURL.path)
    }

    func select(_ url: URL?) {
        let standardizedURL = url?.standardizedFileURL
        guard selectedURL != standardizedURL else { return }

        selectedURL = standardizedURL
        scheduleObserverNotification()
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func persist() {
        persistence.openFolderBookmarks = folderURLs.compactMap(bookmarkData)
        persistence.openFolderExpandedPaths = Array(expandedFolderPaths)
    }

    private func currentState() -> State {
        State(
            folderURLs: folderURLs,
            selectedURL: selectedURL,
            expandedFolderPaths: expandedFolderPaths
        )
    }

    private func notifyObservers() {
        let state = currentState()
        for observer in observers.values {
            observer(state)
        }
    }

    private func scheduleObserverNotification() {
        guard !isObserverNotificationScheduled else { return }

        isObserverNotificationScheduled = true
        Task { @MainActor in
            self.isObserverNotificationScheduled = false
            self.notifyObservers()
        }
    }

    private func storedFolderURLs() -> [URL] {
        persistence.openFolderBookmarks.compactMap(resolveURL)
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
