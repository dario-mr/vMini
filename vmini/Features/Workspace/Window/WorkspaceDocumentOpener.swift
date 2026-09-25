import AppKit

struct DocumentOpenFailure: Sendable {
    let url: URL
    let message: String
}

@MainActor
final class WorkspaceDocumentOpener {
    typealias PayloadLoader = (URL) async throws -> DocumentPayload

    private let documentController: NSDocumentController
    private let openDocumentsStore: OpenDocumentsStore
    private let payloadLoader: PayloadLoader

    init(
        documentController: NSDocumentController,
        openDocumentsStore: OpenDocumentsStore,
        payloadLoader: @escaping PayloadLoader = DocumentPayloadLoader.load(from:)
    ) {
        self.documentController = documentController
        self.openDocumentsStore = openDocumentsStore
        self.payloadLoader = payloadLoader
    }

    convenience init() {
        self.init(documentController: .shared, openDocumentsStore: .shared)
    }

    func openInBackground(
        _ urls: [URL],
        activate activeURL: URL?,
        fallbackDocument: Document?,
        presentDocument: @escaping (Document) -> Void,
        noDocumentFallback: @escaping () -> Void
    ) async -> [DocumentOpenFailure] {
        var failures: [DocumentOpenFailure] = []
        var lastOpenedDocument: Document?

        for url in urls.map(\.standardizedFileURL) {
            do {
                lastOpenedDocument = try await openDocumentInBackground(at: url)
            } catch {
                failures.append(DocumentOpenFailure(url: url, message: error.localizedDescription))
            }
        }

        if
            let activeURL = activeURL?.standardizedFileURL,
            let document = documentController.document(for: activeURL) as? Document
        {
            presentDocument(document)
        } else if
            let lastOpenedDocument,
            openDocumentsStore.contains(lastOpenedDocument)
        {
            presentDocument(lastOpenedDocument)
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

        return failures
    }

    func restoreSession(
        _ references: [RestorableDocumentReference],
        activate activeIdentifier: String?,
        presentDocument: (Document) -> Void,
        noDocumentFallback: () -> Void
    ) async -> (didRestore: Bool, failures: [DocumentOpenFailure]) {
        guard !references.isEmpty else {
            noDocumentFallback()
            return (false, [])
        }

        let activeIndex = references.firstIndex { $0.persistenceIdentifier == activeIdentifier }
            ?? references.indices.last
        let loadingOrder = ([activeIndex].compactMap { $0 } + references.indices.filter { $0 != activeIndex })
        var restoredDocuments: [Int: Document] = [:]
        var failures: [DocumentOpenFailure] = []

        for index in loadingOrder {
            let reference = references[index]
            do {
                let document = try await restoreDocument(reference, at: index)
                restoredDocuments[index] = document
                if index == activeIndex {
                    presentDocument(document)
                }
            } catch {
                let url: URL
                if case .file(let path) = reference {
                    url = URL(fileURLWithPath: path).standardizedFileURL
                } else {
                    continue
                }
                failures.append(DocumentOpenFailure(url: url, message: error.localizedDescription))
            }
        }

        if restoredDocuments.isEmpty {
            noDocumentFallback()
        } else if activeIndex.map({ restoredDocuments[$0] == nil }) ?? true,
                  let fallbackDocument = restoredDocuments.sorted(by: { $0.key < $1.key }).last?.value {
            presentDocument(fallbackDocument)
        }

        return (!restoredDocuments.isEmpty, failures)
    }

    private func openDocumentInBackground(at url: URL) async throws -> Document {
        let standardizedURL = url.standardizedFileURL
        documentController.noteNewRecentDocumentURL(standardizedURL)

        if let existing = documentController.document(for: standardizedURL) as? Document {
            return existing
        }

        let payload = try await payloadLoader(standardizedURL)
        if let existing = documentController.document(for: standardizedURL) as? Document {
            return existing
        }

        let document = Document()
        install(payload, into: document)
        documentController.addDocument(document)
        openDocumentsStore.register(document, activateIfEmpty: false)
        return document
    }

    private func restoreDocument(_ reference: RestorableDocumentReference, at index: Int) async throws -> Document {
        let document: Document
        switch reference {
        case .untitled(let sessionIdentifier):
            document = Document(sessionIdentifier: sessionIdentifier)
        case .file(let path):
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if let existing = documentController.document(for: url) as? Document {
                document = existing
            } else {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let payload = try await payloadLoader(url)
                if let existing = documentController.document(for: url) as? Document {
                    document = existing
                } else {
                    document = Document()
                    install(payload, into: document)
                }
            }
        }

        if !openDocumentsStore.contains(document) {
            if documentController.documents.contains(where: { $0 === document }) == false {
                documentController.addDocument(document)
            }
            openDocumentsStore.register(document, at: index, activateIfEmpty: false)
        }

        return document
    }

    private func install(_ payload: DocumentPayload, into document: Document) {
        document.installLoadedContent(payload.text, ofType: payload.typeName)
        document.fileURL = payload.url
        document.fileType = payload.typeName
        document.updateChangeCount(.changeCleared)
        document.undoManager?.removeAllActions()
    }
}
