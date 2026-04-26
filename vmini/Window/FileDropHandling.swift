import AppKit

@MainActor
protocol FileDropContentViewDelegate: AnyObject {
    func fileDropContentView(_ view: FileDropContentView, didReceiveFileURLs urls: [URL])
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
        let urls = sender.draggingPasteboard.fileURLs()
        guard !urls.isEmpty else { return false }

        dropDelegate?.fileDropContentView(self, didReceiveFileURLs: urls)
        return true
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileURLs().isEmpty ? [] : .copy
    }
}

final class FileDropTextView: NSTextView {
    var onFileURLsDropped: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileURLs().isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileURLs().isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.fileURLs()
        guard !urls.isEmpty else {
            return super.performDragOperation(sender)
        }

        onFileURLsDropped?(urls)
        return true
    }
}

extension NSPasteboard {
    func fileURLs() -> [URL] {
        let options: [ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]

        return readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { $0 as? URL }
            .filter { !$0.hasDirectoryPath } ?? []
    }
}

@MainActor
enum DroppedFileOpener {
    static func open(_ urls: [URL], tabbedIn targetWindow: NSWindow) {
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
                if let error {
                    NSLog("Could not open dropped file %@: %@", url.path as NSString, error.localizedDescription)
                    return
                }

                guard
                    let openedWindow = document?.windowControllers.first?.window,
                    openedWindow !== targetWindow
                else {
                    targetWindow.makeKeyAndOrderFront(nil)
                    return
                }

                targetWindow.addTabbedWindow(openedWindow, ordered: .above)
                openedWindow.makeKeyAndOrderFront(nil)
            }
        }
    }
}
