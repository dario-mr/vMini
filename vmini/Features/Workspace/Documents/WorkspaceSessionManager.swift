import AppKit

@MainActor
final class WorkspaceSessionManager {
    private struct SessionSnapshot: Codable, Equatable {
        let documentReferences: [RestorableDocumentReference]
        let activeDocumentReference: RestorableDocumentReference?
    }

    private let persistence: WorkspacePersistence
    private let openDocumentsStore: OpenDocumentsStore
    private let documentRouter: WorkspaceDocumentRouting
    private var isTerminationSnapshotLocked = false

    init(
        persistence: WorkspacePersistence,
        openDocumentsStore: OpenDocumentsStore,
        documentRouter: WorkspaceDocumentRouting
    ) {
        self.persistence = persistence
        self.openDocumentsStore = openDocumentsStore
        self.documentRouter = documentRouter
    }

    func saveOpenFiles() {
        guard !isTerminationSnapshotLocked else { return }

        persist(
            SessionSnapshot(
                documentReferences: openDocumentsStore.documents.map(restorableReference(for:)),
                activeDocumentReference: openDocumentsStore.activeDocument.map(restorableReference(for:))
            )
        )
    }

    func prepareForTermination() {
        saveOpenFiles()
        isTerminationSnapshotLocked = true
    }

    func cancelTermination() {
        isTerminationSnapshotLocked = false
        saveOpenFiles()
    }

    @discardableResult
    func reopenLastFiles() -> Bool {
        guard let snapshot = restoredSnapshot() else {
            return false
        }

        return documentRouter.restoreSession(
            snapshot.documentReferences,
            activate: snapshot.activeDocumentReference?.persistenceIdentifier
        )
    }

    func restoredDocumentReferences() -> [RestorableDocumentReference]? {
        restoredSnapshot()?.documentReferences
    }

    func restoredActiveDocumentReference() -> RestorableDocumentReference? {
        restoredSnapshot()?.activeDocumentReference
    }

    private func restoredSnapshot() -> SessionSnapshot? {
        guard let data = persistence.sessionDocumentReferencesData else {
            return nil
        }

        let decoder = JSONDecoder()

        guard let documentReferences = try? decoder.decode([RestorableDocumentReference].self, from: data) else {
            return nil
        }

        let activeDocumentReference = persistence.sessionActiveDocumentReferenceData
            .flatMap { try? decoder.decode(RestorableDocumentReference.self, from: $0) }

        return SessionSnapshot(
            documentReferences: documentReferences,
            activeDocumentReference: activeDocumentReference
        )
    }

    private func persist(_ snapshot: SessionSnapshot) {
        let encoder = JSONEncoder()

        if let documentData = try? encoder.encode(snapshot.documentReferences) {
            persistence.sessionDocumentReferencesData = documentData
        }

        if let activeDocumentReference = snapshot.activeDocumentReference,
           let activeData = try? encoder.encode(activeDocumentReference) {
            persistence.sessionActiveDocumentReferenceData = activeData
        } else {
            persistence.sessionActiveDocumentReferenceData = nil
        }
    }

    private func restorableReference(for document: Document) -> RestorableDocumentReference {
        if let fileURL = document.fileURL {
            return .file(path: fileURL.standardizedFileURL.path)
        }

        return .untitled(sessionID: document.sessionIdentifier)
    }
}
