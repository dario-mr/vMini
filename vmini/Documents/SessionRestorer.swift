import AppKit

@MainActor
enum SessionRestorer {
    static func saveOpenFiles() {
        let openFileBookmarks = NSDocumentController.shared.documents.compactMap { document -> Data? in
            guard let url = document.fileURL else {
                return nil
            }

            return bookmarkData(for: url)
        }

        UserDefaults.standard.set(openFileBookmarks, forKey: UserDefaultsKeys.sessionRestorerOpenFiles)
        UserDefaults.standard.set(
            NSDocumentController.shared.currentDocument?.fileURL.flatMap(bookmarkData(for:)),
            forKey: UserDefaultsKeys.sessionRestorerActiveFile
        )
    }

    static func reopenLastFiles() {
        guard let bookmarkData = UserDefaults.standard.array(forKey: UserDefaultsKeys.sessionRestorerOpenFiles) as? [Data] else {
            return
        }

        let urls = bookmarkData.compactMap(resolveURL(from:))
        guard !urls.isEmpty else { return }

        let activeURL = (UserDefaults.standard.data(forKey: UserDefaultsKeys.sessionRestorerActiveFile))
            .flatMap(resolveURL(from:))
        var pendingRestores = urls.count

        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error {
                    NSLog("Skipping session restore for %@: %@", url.path as NSString, error.localizedDescription)
                }

                pendingRestores -= 1
                focusRestoredDocumentIfNeeded(for: activeURL, pendingRestores: pendingRestores)
            }
        }
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

    private static func focusRestoredDocumentIfNeeded(for activeURL: URL?, pendingRestores: Int) {
        guard pendingRestores == 0 else { return }
        guard let activeURL else { return }
        guard let document = NSDocumentController.shared.document(for: activeURL) else { return }
        guard let window = document.windowControllers.first?.window else { return }

        window.makeKeyAndOrderFront(nil)
    }
}
