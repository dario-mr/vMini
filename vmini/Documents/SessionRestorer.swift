import AppKit

@MainActor
enum SessionRestorer {
    static func saveOpenFiles() {
        let openFileBookmarks = OpenDocumentsStore.shared.documents.compactMap { document -> Data? in
            guard let url = document.fileURL else {
                return nil
            }

            return bookmarkData(for: url)
        }

        UserDefaults.standard.set(openFileBookmarks, forKey: UserDefaultsKeys.sessionRestorerOpenFiles)
        UserDefaults.standard.set(
            OpenDocumentsStore.shared.activeDocument?.fileURL.flatMap(bookmarkData(for:)),
            forKey: UserDefaultsKeys.sessionRestorerActiveFile
        )
    }

    @discardableResult
    static func reopenLastFiles() -> Bool {
        guard let bookmarkData = UserDefaults.standard.array(forKey: UserDefaultsKeys.sessionRestorerOpenFiles) as? [Data] else {
            return false
        }

        let urls = bookmarkData.compactMap(resolveURL(from:))
        guard !urls.isEmpty else { return false }

        let activeURL = (UserDefaults.standard.data(forKey: UserDefaultsKeys.sessionRestorerActiveFile))
            .flatMap(resolveURL(from:))
        WorkspaceWindowController.shared.open(urls: urls, activate: activeURL)
        return true
    }

    private static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolveURL(from data: Data) -> URL? {
        var isStale = false

        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ),
        !isStale,
        FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url
    }
}
