import AppKit

@MainActor
protocol WorkspaceDocumentRouting: AnyObject {
    func present(document: Document)
    func open(urls: [URL], activate activeURL: URL?)
    func createUntitledDocument()
    func createUntitledDocument(sessionIdentifier: UUID)
    func restoreSession(_ references: [RestorableDocumentReference], activate activeIdentifier: String?) async -> Bool
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
    private var documentsBeingReviewedForClose = Set<ObjectIdentifier>()
    private var closeReviewCompletions: [ObjectIdentifier: (Bool) -> Void] = [:]
    private var isReviewingBulkClose = false
    private var selectionIntent: UInt64 = 0

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
        selectionIntent &+= 1
        if !openDocumentsStore.contains(document) {
            documentController.addDocument(document)
            openDocumentsStore.register(document)
        }

        openDocumentsStore.select(document)
        onDocumentPresentationRequested?()
    }

    func open(urls: [URL], activate activeURL: URL? = nil) {
        let fallbackDocument = openDocumentsStore.activeDocument
        let requestIntent = beginSelectionIntent()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let failures = await AppPerformanceProfiler.measure("WorkspaceOpen") {
                await documentOpener.openInBackground(
                    urls,
                    activate: activeURL,
                    fallbackDocument: fallbackDocument,
                    presentDocument: { [weak self] document in
                        guard let self, selectionIntent == requestIntent else { return }
                        present(document: document)
                    },
                    noDocumentFallback: { [weak self] in
                        guard let self, selectionIntent == requestIntent else { return }
                        onNeedsWindowStateRefresh?()
                    }
                )
            }
            presentOpenFailures(failures)
        }
    }

    func createUntitledDocument() {
        present(document: Document())
    }

    func createUntitledDocument(sessionIdentifier: UUID) {
        present(document: Document(sessionIdentifier: sessionIdentifier))
    }

    @discardableResult
    func restoreSession(_ references: [RestorableDocumentReference], activate activeIdentifier: String?) async -> Bool {
        let requestIntent = beginSelectionIntent()
        let result = await documentOpener.restoreSession(
            references,
            activate: activeIdentifier,
            presentDocument: { [weak self] document in
                guard let self, selectionIntent == requestIntent else { return }
                present(document: document)
            },
            noDocumentFallback: { [weak self] in
                guard let self, selectionIntent == requestIntent else { return }
                onNeedsWindowStateRefresh?()
            }
        )
        presentOpenFailures(result.failures)
        return result.didRestore
    }

    private func beginSelectionIntent() -> UInt64 {
        selectionIntent &+= 1
        return selectionIntent
    }

    private func presentOpenFailures(_ failures: [DocumentOpenFailure]) {
        guard !failures.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = failures.count == 1 ? "Could Not Open File" : "Could Not Open Files"
        alert.informativeText = failures.map {
            "\($0.url.lastPathComponent): \($0.message)"
        }.joined(separator: "\n\n")
        alert.addButton(withTitle: "OK")

        if let window = WorkspaceWindowController.shared.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func closeCurrentDocument() {
        guard let document = openDocumentsStore.activeDocument else { return }
        close(document: document)
    }

    func close(document: Document) {
        guard !isReviewingBulkClose else { return }
        reviewAndClose(document)
    }

    func close(documents: [Document]) {
        guard !isReviewingBulkClose else { return }
        isReviewingBulkClose = true
        reviewNextDocument(in: documents, at: 0)
    }

    private func reviewNextDocument(in documents: [Document], at index: Int) {
        guard index < documents.count else {
            isReviewingBulkClose = false
            return
        }

        reviewAndClose(documents[index]) { [weak self] didClose in
            guard let self else { return }
            guard didClose else {
                isReviewingBulkClose = false
                return
            }
            Task { @MainActor [weak self] in
                self?.reviewNextDocument(in: documents, at: index + 1)
            }
        }
    }

    private func reviewAndClose(_ document: Document, completion: ((Bool) -> Void)? = nil) {
        let identifier = ObjectIdentifier(document)
        guard openDocumentsStore.contains(document), documentsBeingReviewedForClose.insert(identifier).inserted else {
            completion?(false)
            return
        }

        if let completion {
            closeReviewCompletions[identifier] = completion
        }
        document.canClose(withDelegate: self, shouldClose: #selector(document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    @objc
    private func document(_ document: NSDocument, shouldClose shouldCloseDocument: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let identifier = ObjectIdentifier(document)
        documentsBeingReviewedForClose.remove(identifier)
        let completion = closeReviewCompletions.removeValue(forKey: identifier)

        var didClose = false
        if shouldCloseDocument, let document = document as? Document {
            document.close()
            if !openDocumentsStore.contains(document) {
                didClose = true
                closedDocumentHistory.record(document: document)
                if openDocumentsStore.documents.isEmpty {
                    onNeedsWindowStateRefresh?()
                }
            }
        }
        completion?(didClose)
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
