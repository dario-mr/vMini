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
        reopen(urls, at: 0, activeURL: activeURL)
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

    private static func reopen(_ urls: [URL], at index: Int, activeURL: URL?) {
        guard index < urls.count else {
            refreshAllTabTitles()
            focusRestoredDocumentIfNeeded(for: activeURL)
            return
        }

        let url = urls[index]
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSLog("Skipping session restore for %@: %@", url.path as NSString, error.localizedDescription)
            }

            reopen(urls, at: index + 1, activeURL: activeURL)
        }
    }

    private static func focusRestoredDocumentIfNeeded(for activeURL: URL?) {
        guard let activeURL else { return }
        guard let document = NSDocumentController.shared.document(for: activeURL) else { return }
        guard let window = document.windowControllers.first?.window else { return }

        window.makeKeyAndOrderFront(nil)
    }

    private static func refreshAllTabTitles() {
        for case let document as Document in NSDocumentController.shared.documents {
            for case let windowController as EditorWindowController in document.windowControllers {
                EditorWindowController.refreshTabGroupTitles(for: windowController.window)
            }
        }
    }
}
