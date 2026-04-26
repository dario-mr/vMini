import AppKit
import UniformTypeIdentifiers

@MainActor
final class Document: NSDocument {
    static let supportedTypes: [UTType] = [.plainText, .text]

    private var text = ""
    private weak var editorViewController: EditorViewController?

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
        let editorViewController = EditorViewController()
        editorViewController.text = text
        editorViewController.onTextChanged = { [weak self] updatedText in
            guard let self else { return }
            let wasEdited = isDocumentEdited
            text = updatedText
            updateChangeCount(.changeDone)

            if wasEdited != isDocumentEdited {
                OpenDocumentsStore.postDidChange()
            }
        }

        let windowController = EditorWindowController(document: self, editorViewController: editorViewController)
        addWindowController(windowController)
        self.editorViewController = editorViewController
        updateWindowTitles()
        OpenDocumentsStore.postDidChange()
    }

    override func close() {
        super.close()
        OpenDocumentsStore.postDidChange()
    }

    override func save(_ sender: Any?) {
        super.save(sender)
        OpenDocumentsStore.postDidChange()
    }

    override func saveAs(_ sender: Any?) {
        super.saveAs(sender)
        OpenDocumentsStore.postDidChange()
    }

    private func updateWindowTitles() {
        for case let windowController as EditorWindowController in windowControllers {
            windowController.updateTitles(for: self)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        return data
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
}
