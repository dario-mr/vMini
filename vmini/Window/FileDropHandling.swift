import AppKit

@MainActor
protocol FileDropContentViewDelegate: AnyObject {
    func fileDropContentView(_ view: FileDropContentView, didReceiveFileSystemURLs urls: [URL])
}

final class FileDropContentView: NSView {
    weak var dropDelegate: FileDropContentViewDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.fileSystemURLs()
        guard !urls.isEmpty else { return false }

        dropDelegate?.fileDropContentView(self, didReceiveFileSystemURLs: urls)
        return true
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileSystemURLs().isEmpty ? [] : .copy
    }
}

final class FileDropTextView: NSTextView {
    var onFileSystemURLsDropped: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileSystemURLs().isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileSystemURLs().isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.fileSystemURLs()
        guard !urls.isEmpty else {
            return super.performDragOperation(sender)
        }

        onFileSystemURLsDropped?(urls)
        return true
    }
}

extension NSPasteboard {
    func fileSystemURLs() -> [URL] {
        let options: [ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]

        return readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { ($0 as? URL)?.standardizedFileURL } ?? []
    }
}

@MainActor
enum OpenURLRouter {
    static func open(_ urls: [URL], tabbedIn targetWindow: NSWindow?) {
        let folders = urls.filter(isDirectory)
        let files = urls.filter { !isDirectory($0) }

        OpenFoldersStore.shared.add(folders)
        openFiles(files, tabbedIn: targetWindow, at: 0)
    }

    private static func openFiles(_ urls: [URL], tabbedIn targetWindow: NSWindow?, at index: Int) {
        guard index < urls.count else {
            EditorWindowController.refreshTabGroupTitles(for: targetWindow)
            return
        }

        let url = urls[index]
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error {
                NSLog("Could not open dropped file %@: %@", url.path as NSString, error.localizedDescription)
                openFiles(urls, tabbedIn: targetWindow, at: index + 1)
                return
            }

            guard let targetWindow else {
                let openedWindow = document?.windowControllers.first?.window
                openedWindow?.makeKeyAndOrderFront(nil)
                EditorWindowController.refreshTabGroupTitles(for: openedWindow)
                openFiles(urls, tabbedIn: targetWindow, at: index + 1)
                return
            }

            guard
                let openedWindow = document?.windowControllers.first?.window,
                openedWindow !== targetWindow
            else {
                targetWindow.makeKeyAndOrderFront(nil)
                EditorWindowController.refreshTabGroupTitles(for: targetWindow)
                openFiles(urls, tabbedIn: targetWindow, at: index + 1)
                return
            }

            targetWindow.addTabbedWindow(openedWindow, ordered: .above)
            openedWindow.makeKeyAndOrderFront(nil)
            EditorWindowController.refreshTabGroupTitles(for: targetWindow)
            openFiles(urls, tabbedIn: targetWindow, at: index + 1)
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
