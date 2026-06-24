import AppKit

@MainActor
protocol WorkspaceDocumentRouting: AnyObject {
    func present(document: Document)
    func open(urls: [URL], activate activeURL: URL?)
    func createUntitledDocument()
    func createUntitledDocument(sessionIdentifier: UUID)
    func restoreSession(_ references: [RestorableDocumentReference], activate activeIdentifier: String?) -> Bool
    func closeCurrentDocument()
    func close(document: Document)
    func reopenMostRecentClosedDocument()
}

@MainActor
final class WorkspaceDocumentCoordinator: WorkspaceDocumentRouting {
    static let shared = WorkspaceDocumentCoordinator()

    var onDocumentPresentationRequested: (() -> Void)?
    var onNeedsWindowStateRefresh: (() -> Void)?

    private let documentOpener: WorkspaceDocumentOpener
    private let openDocumentsStore: OpenDocumentsStore
    private let closedDocumentHistory: ClosedDocumentHistory
    private let documentController: NSDocumentController

    init(
        documentOpener: WorkspaceDocumentOpener,
        openDocumentsStore: OpenDocumentsStore,
        closedDocumentHistory: ClosedDocumentHistory,
        documentController: NSDocumentController
    ) {
        self.documentOpener = documentOpener
        self.openDocumentsStore = openDocumentsStore
        self.closedDocumentHistory = closedDocumentHistory
        self.documentController = documentController
    }

    convenience init() {
        self.init(
            documentOpener: WorkspaceDocumentOpener(),
            openDocumentsStore: .shared,
            closedDocumentHistory: .shared,
            documentController: .shared
        )
    }

    func present(document: Document) {
        if !openDocumentsStore.contains(document) {
            documentController.addDocument(document)
            openDocumentsStore.register(document)
        }

        openDocumentsStore.select(document)
        onDocumentPresentationRequested?()
    }

    func open(urls: [URL], activate activeURL: URL? = nil) {
        let fallbackDocument = openDocumentsStore.activeDocument
        Task { @MainActor [weak self] in
            guard let self else { return }
            await documentOpener.openInBackground(
                urls,
                activate: activeURL,
                fallbackDocument: fallbackDocument,
                presentDocument: { [weak self] document in
                    self?.present(document: document)
                },
                noDocumentFallback: { [weak self] in
                    self?.onNeedsWindowStateRefresh?()
                }
            )
        }
    }

    func createUntitledDocument() {
        present(document: Document())
    }

    func createUntitledDocument(sessionIdentifier: UUID) {
        present(document: Document(sessionIdentifier: sessionIdentifier))
    }

    @discardableResult
    func restoreSession(_ references: [RestorableDocumentReference], activate activeIdentifier: String?) -> Bool {
        documentOpener.restoreSession(
            references,
            activate: activeIdentifier,
            presentDocument: { [weak self] document in
                self?.present(document: document)
            },
            noDocumentFallback: { [weak self] in
                self?.onNeedsWindowStateRefresh?()
            }
        )
    }

    func closeCurrentDocument() {
        guard let document = openDocumentsStore.activeDocument else { return }
        close(document: document)
    }

    func close(document: Document) {
        document.close()

        guard !openDocumentsStore.contains(document) else {
            return
        }

        closedDocumentHistory.record(document: document)

        if openDocumentsStore.documents.isEmpty {
            onNeedsWindowStateRefresh?()
        }
    }

    func reopenMostRecentClosedDocument() {
        guard let reference = closedDocumentHistory.popMostRecent() else { return }

        switch reference {
        case .file(let path):
            let fileURL = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            open(urls: [fileURL], activate: fileURL)
        case .untitled(let sessionID):
            createUntitledDocument(sessionIdentifier: sessionID)
        }
    }

    var activeWindowTitle: String {
        openDocumentsStore.activeDocument?.windowTitle ?? "vMini"
    }

    var activeRepresentedURL: URL? {
        openDocumentsStore.activeDocument?.fileURL
    }
}
