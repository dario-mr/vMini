import AppKit
import UniformTypeIdentifiers

@MainActor
final class WorkspaceDocumentOpener {
    private struct OpenDocumentPayload: Sendable {
        let url: URL
        let typeName: String
        let data: Data
    }

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

    func openInBackground(
        _ urls: [URL],
        activate activeURL: URL?,
        fallbackDocument: Document?,
        presentDocument: @escaping (Document) -> Void,
        noDocumentFallback: @escaping () -> Void
    ) async {
        let standardized = urls.map(\.standardizedFileURL)

        for url in standardized {
            do {
                _ = try await openDocumentInBackground(at: url)
            } catch {
                NSLog("Could not open file %@: %@", url.path as NSString, error.localizedDescription)
            }
        }

        if
            let activeURL = activeURL?.standardizedFileURL,
            let document = documentController.document(for: activeURL) as? Document
        {
            presentDocument(document)
        } else if activeURL == nil, let lastDocument = openDocumentsStore.documents.last {
            presentDocument(lastDocument)
        } else if
            let fallbackDocument,
            openDocumentsStore.contains(fallbackDocument)
        {
            presentDocument(fallbackDocument)
        } else if let firstDocument = openDocumentsStore.documents.first {
            presentDocument(firstDocument)
        } else {
            noDocumentFallback()
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

    private func openDocumentInBackground(at url: URL, trackRecentDocument: Bool = true) async throws -> Document {
        let standardizedURL = url.standardizedFileURL

        if trackRecentDocument {
            documentController.noteNewRecentDocumentURL(standardizedURL)
        }

        if let existing = documentController.document(for: standardizedURL) as? Document {
            return existing
        }

        let payload = try await Task.detached(priority: .userInitiated) {
            try OpenDocumentPayload(
                url: standardizedURL,
                typeName: Self.inferredTypeForDocument(at: standardizedURL),
                data: Data(contentsOf: standardizedURL, options: [.mappedIfSafe])
            )
        }.value

        if let existing = documentController.document(for: standardizedURL) as? Document {
            return existing
        }

        let document = Document()
        try document.read(from: payload.data, ofType: payload.typeName)
        document.fileType = payload.typeName
        document.fileURL = payload.url
        document.updateChangeCount(.changeCleared)
        document.undoManager?.removeAllActions()
        documentController.addDocument(document)
        openDocumentsStore.register(document)
        return document
    }

    private nonisolated static func inferredTypeForDocument(at url: URL) throws -> String {
        if
            let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
            Document.supportedTypes.contains(where: { contentType.conforms(to: $0) })
        {
            return contentType.identifier
        }

        if
            let inferredType = UTType(filenameExtension: url.pathExtension),
            Document.supportedTypes.contains(where: { inferredType.conforms(to: $0) })
        {
            return inferredType.identifier
        }

        if looksLikeTextFile(at: url) {
            return UTType.plainText.identifier
        }

        return UTType.plainText.identifier
    }

    private func inferredTypeForDocument(at url: URL) throws -> String {
        try Self.inferredTypeForDocument(at: url)
    }

    private nonisolated static func looksLikeTextFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 4096) else {
            return false
        }

        if data.contains(0) {
            return false
        }

        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .ascii]
        return encodings.contains { String(data: data, encoding: $0) != nil }
    }
}
