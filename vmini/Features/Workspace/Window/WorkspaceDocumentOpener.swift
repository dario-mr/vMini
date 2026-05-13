import AppKit

@MainActor
final class WorkspaceDocumentOpener {
    private let documentController: NSDocumentController
    private let openDocumentsStore: OpenDocumentsStore

    init(documentController: NSDocumentController, openDocumentsStore: OpenDocumentsStore) {
        self.documentController = documentController
        self.openDocumentsStore = openDocumentsStore
    }

    convenience init() {
        self.init(documentController: .shared, openDocumentsStore: .shared)
    }

    func open(
        _ urls: [URL],
        activate activeURL: URL?,
        fallbackDocument: Document?,
        presentDocument: (Document) -> Void,
        noDocumentFallback: () -> Void
    ) {
        let standardized = urls.map(\.standardizedFileURL)
        openDocumentsStore.performBatchUpdate {
            open(
                standardized,
                index: 0,
                activate: activeURL?.standardizedFileURL,
                fallbackDocument: fallbackDocument,
                presentDocument: presentDocument,
                noDocumentFallback: noDocumentFallback
            )
        }
    }

    @discardableResult
    func restoreSession(
        _ references: [RestorableDocumentReference],
        activate activeIdentifier: String?,
        presentDocument: (Document) -> Void,
        noDocumentFallback: () -> Void
    ) -> Bool {
        var restoredDocuments: [(identifier: String, document: Document)] = []

        openDocumentsStore.performBatchUpdate {
            for reference in references {
                switch reference {
                case .file(let path):
                    let fileURL = URL(fileURLWithPath: path).standardizedFileURL
                    guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

                    do {
                        let document = try openDocument(at: fileURL, trackRecentDocument: false)
                        restoredDocuments.append((reference.persistenceIdentifier, document))
                    } catch {
                        NSLog("Could not reopen file %@: %@", fileURL.path as NSString, error.localizedDescription)
                    }
                case .untitled(let sessionIdentifier):
                    let document = Document(sessionIdentifier: sessionIdentifier)
                    documentController.addDocument(document)
                    openDocumentsStore.register(document)
                    restoredDocuments.append((reference.persistenceIdentifier, document))
                }
            }
        }

        guard !restoredDocuments.isEmpty else {
            return false
        }

        let activeDocument = restoredDocuments.first(where: { $0.identifier == activeIdentifier })?.document
            ?? restoredDocuments.last?.document
        if let activeDocument {
            presentDocument(activeDocument)
        } else {
            noDocumentFallback()
        }
        return true
    }

    private func open(
        _ urls: [URL],
        index: Int,
        activate activeURL: URL?,
        fallbackDocument: Document?,
        presentDocument: (Document) -> Void,
        noDocumentFallback: () -> Void
    ) {
        guard index < urls.count else {
            if
                let activeURL,
                let document = documentController.document(for: activeURL) as? Document
            {
                presentDocument(document)
            } else if
                let fallbackDocument,
                openDocumentsStore.contains(fallbackDocument)
            {
                presentDocument(fallbackDocument)
            } else if let first = openDocumentsStore.documents.first {
                presentDocument(first)
            } else {
                noDocumentFallback()
            }
            return
        }

        let url = urls[index]

        do {
            let document = try openDocument(at: url)

            if activeURL == nil, index == urls.count - 1 {
                presentDocument(document)
            } else {
                openDocumentsStore.refresh()
            }
        } catch {
            NSLog("Could not open file %@: %@", url.path as NSString, error.localizedDescription)
        }

        open(
            urls,
            index: index + 1,
            activate: activeURL,
            fallbackDocument: fallbackDocument,
            presentDocument: presentDocument,
            noDocumentFallback: noDocumentFallback
        )
    }

    private func openDocument(at url: URL, trackRecentDocument: Bool = true) throws -> Document {
        let standardizedURL = url.standardizedFileURL

        if trackRecentDocument {
            documentController.noteNewRecentDocumentURL(standardizedURL)
        }

        if let existing = documentController.document(for: standardizedURL) as? Document {
            return existing
        }

        let document = Document()
        let typeName = try inferredTypeForDocument(at: standardizedURL)
        let data = try Data(contentsOf: standardizedURL, options: [.mappedIfSafe])

        try document.read(from: data, ofType: typeName)
        document.fileType = typeName
        document.fileURL = standardizedURL
        document.updateChangeCount(.changeCleared)
        document.undoManager?.removeAllActions()
        documentController.addDocument(document)
        openDocumentsStore.register(document)
        return document
    }

    private func inferredTypeForDocument(at url: URL) throws -> String {
        if let controller = documentController as? DocumentController {
            return try controller.typeForContents(of: url)
        }

        return try DocumentController().typeForContents(of: url)
    }
}
