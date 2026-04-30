import AppKit
import UniformTypeIdentifiers

@MainActor
final class Document: NSDocument {
    static let supportedTypes: [UTType] = [.plainText, .text]

    private var text = ""
    private var editorViewController: EditorViewController?
    private let externalChangeWatcher = DocumentFileWatcher()

    var sidebarTitle: String {
        fileURL?.lastPathComponent ?? displayName
    }

    var windowTitle: String {
        guard let fileURL else {
            return displayName
        }

        return (fileURL.path as NSString).abbreviatingWithTildeInPath
    }

    override init() {
        super.init()
        hasUndoManager = true
    }

    override var fileURL: URL? {
        didSet {
            Task { @MainActor in
                guard fileURL != oldValue else { return }
                restartExternalChangeWatcher()
                updateWindowTitles()
                OpenDocumentsStore.postDidChange()
            }
        }
    }

    override class var readableTypes: [String] {
        supportedTypes.map(\.identifier)
    }

    override class var writableTypes: [String] {
        supportedTypes.map(\.identifier)
    }

    override class var autosavesInPlace: Bool {
        false
    }

    override func makeWindowControllers() {
        WorkspaceWindowController.shared.present(document: self)
    }

    override func close() {
        externalChangeWatcher.stop()
        editorViewController = nil
        super.close()
        if OpenDocumentsStore.shared.activeDocument === self {
            OpenDocumentsStore.shared.select(OpenDocumentsStore.shared.documents.first)
        } else {
            OpenDocumentsStore.postDidChange()
        }
    }

    override func save(_ sender: Any?) {
        externalChangeWatcher.stop()
        super.save(sender)
        restartExternalChangeWatcher()
        OpenDocumentsStore.postDidChange()
    }

    override func saveAs(_ sender: Any?) {
        externalChangeWatcher.stop()
        super.saveAs(sender)
        restartExternalChangeWatcher()
        OpenDocumentsStore.postDidChange()
    }

    private func updateWindowTitles() {
        OpenDocumentsStore.postDidChange()
    }

    private func restartExternalChangeWatcher() {
        externalChangeWatcher.watch(fileURL: fileURL) { [weak self] restartWatcher in
            self?.reloadFromDiskAfterExternalChange(restartWatcher: restartWatcher)
        }
    }

    private func reloadFromDiskAfterExternalChange(restartWatcher: Bool) {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let typeName = try NSDocumentController.shared.typeForContents(of: fileURL)
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            try read(from: data, ofType: typeName)
            updateChangeCount(.changeCleared)
            undoManager?.removeAllActions()
            OpenDocumentsStore.postDidChange()

            if restartWatcher {
                externalChangeWatcher.watch(fileURL: fileURL) { [weak self] restartWatcher in
                    self?.reloadFromDiskAfterExternalChange(restartWatcher: restartWatcher)
                }
            }
        } catch {
            NSLog("Could not reload externally changed file %@: %@", fileURL.path as NSString, error.localizedDescription)
        }
    }

    override func write(to url: URL, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            let currentText = editorViewController?.text ?? text
            text = currentText
            return currentText
        }.write(to: url, atomically: true, encoding: .utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        if let decoded = String(data: data, encoding: .utf8) {
            MainActor.assumeIsolated {
                text = decoded
                editorViewController?.text = decoded
            }
            return
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func resolvedEditorViewController(onFileSystemURLsDropped: @escaping ([URL]) -> Void) -> EditorViewController {
        if let editorViewController {
            editorViewController.onFileSystemURLsDropped = onFileSystemURLsDropped
            return editorViewController
        }

        let editorViewController = EditorViewController()
        editorViewController.text = text
        editorViewController.onTextChanged = { [weak self] in
            guard let self else { return }
            let wasEdited = isDocumentEdited
            updateChangeCount(.changeDone)

            if wasEdited != isDocumentEdited {
                OpenDocumentsStore.postDidChange()
            }
        }
        editorViewController.onFileSystemURLsDropped = onFileSystemURLsDropped
        self.editorViewController = editorViewController
        return editorViewController
    }
}
