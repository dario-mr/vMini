import AppKit

@MainActor
final class WorkspaceWindowController: NSWindowController {
    static let shared = WorkspaceWindowController()

    private let workspaceViewController = EditorContentViewController()
    private let frameAutosaveName = "WorkspaceWindow"

    private init() {
        let window = EditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = workspaceViewController
        window.titleVisibility = .visible
        window.backgroundColor = AppColors.windowBackground
        window.setFrameAutosaveName(frameAutosaveName)
        window.setFrameUsingName(frameAutosaveName)

        super.init(window: window)
        shouldCascadeWindows = true
        synchronizeWindowState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentsDidChange),
            name: OpenDocumentsStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistWindowFrame),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistWindowFrame),
            name: NSWindow.didEndLiveResizeNotification,
            object: window
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func present(document: Document) {
        if !OpenDocumentsStore.shared.documents.contains(where: { $0 === document }) {
            NSDocumentController.shared.addDocument(document)
        }

        OpenDocumentsStore.shared.select(document)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        workspaceViewController.focusActiveEditor()
    }

    func open(urls: [URL], activate activeURL: URL? = nil) {
        let standardized = urls.map(\.standardizedFileURL)
        open(standardized, index: 0, activate: activeURL?.standardizedFileURL)
    }

    func createUntitledDocument() {
        let document = Document()
        present(document: document)
    }

    func closeCurrentDocument() {
        guard let document = OpenDocumentsStore.shared.activeDocument else { return }
        close(document: document)
    }

    func close(document: Document) {
        let documents = OpenDocumentsStore.shared.documents
        let closedIndex = documents.firstIndex(where: { $0 === document }) ?? 0
        let wasActive = OpenDocumentsStore.shared.activeDocument === document
        let remaining = documents.filter { $0 !== document }
        document.close()

        if wasActive {
            let nextSelection: Document?
            if remaining.isEmpty {
                nextSelection = nil
            } else {
                let targetIndex = max(0, min(closedIndex - 1, remaining.count - 1))
                nextSelection = remaining[targetIndex]
            }
            OpenDocumentsStore.shared.select(nextSelection)
        } else {
            OpenDocumentsStore.postDidChange()
        }

        if remaining.isEmpty {
            synchronizeWindowState()
        }
    }

    @objc
    private func handleDocumentsDidChange() {
        synchronizeWindowState()
    }

    @objc
    private func persistWindowFrame() {
        guard let window else { return }
        window.saveFrame(usingName: frameAutosaveName)
    }

    private func open(_ urls: [URL], index: Int, activate activeURL: URL?) {
        guard index < urls.count else {
            if
                let activeURL,
                let document = NSDocumentController.shared.document(for: activeURL) as? Document
            {
                present(document: document)
            } else if let first = OpenDocumentsStore.shared.documents.first {
                present(document: first)
            } else {
                synchronizeWindowState()
            }
            return
        }

        let url = urls[index]

        do {
            let document = try openDocument(at: url)

            if activeURL == nil, index == urls.count - 1 {
                present(document: document)
            } else {
                OpenDocumentsStore.postDidChange()
            }
        } catch {
            NSLog("Could not open file %@: %@", url.path as NSString, error.localizedDescription)
        }

        open(urls, index: index + 1, activate: activeURL)
    }

    private func openDocument(at url: URL) throws -> Document {
        let standardizedURL = url.standardizedFileURL

        if let existing = NSDocumentController.shared.document(for: standardizedURL) as? Document {
            return existing
        }

        let document = Document()
        let typeName = try inferredTypeForDocument(at: standardizedURL)
        let data = try Data(contentsOf: standardizedURL, options: [.mappedIfSafe])

        try document.read(from: data, ofType: typeName)
        document.fileURL = standardizedURL
        document.updateChangeCount(.changeCleared)
        document.undoManager?.removeAllActions()
        NSDocumentController.shared.addDocument(document)
        return document
    }

    private func inferredTypeForDocument(at url: URL) throws -> String {
        if let controller = NSDocumentController.shared as? DocumentController {
            return try controller.typeForContents(of: url)
        }

        return try DocumentController().typeForContents(of: url)
    }

    private func synchronizeWindowState() {
        let title = OpenDocumentsStore.shared.activeDocument?.windowTitle ?? "vMini"
        window?.title = title
        window?.representedURL = OpenDocumentsStore.shared.activeDocument?.fileURL
    }
}
