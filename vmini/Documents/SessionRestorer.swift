import AppKit

@MainActor
enum SessionRestorer {
    private struct SessionSnapshot: Codable {
        let documentReferences: [RestorableDocumentReference]
        let activeDocumentReference: RestorableDocumentReference?
    }

    private static var isTerminationSnapshotLocked = false

    static func saveOpenFiles() {
        guard !isTerminationSnapshotLocked else { return }

        let snapshot = SessionSnapshot(
            documentReferences: OpenDocumentsStore.shared.documents.compactMap { document in
                guard let fileURL = document.fileURL else { return nil }
                return RestorableDocumentReference.file(path: fileURL.standardizedFileURL.path)
            },
            activeDocumentReference: OpenDocumentsStore.shared.activeDocument?.fileURL.map {
                RestorableDocumentReference.file(path: $0.standardizedFileURL.path)
            }
        )
        persist(snapshot)
    }

    static func prepareForTermination() {
        saveOpenFiles()
        isTerminationSnapshotLocked = true
    }

    static func cancelTermination() {
        isTerminationSnapshotLocked = false
        saveOpenFiles()
    }

    @discardableResult
    static func reopenLastFiles() -> Bool {
        if let snapshot = restoredSnapshot() {
            return WorkspaceWindowController.shared.restoreSession(
                snapshot.documentReferences,
                activate: snapshot.activeDocumentReference?.persistenceIdentifier
            )
        }

        guard let storedPaths = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.sessionRestorerOpenFilePaths) else {
            return false
        }

        let urls = storedPaths
            .map(URL.init(fileURLWithPath:))
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return false }

        let activeURL = UserDefaults.standard
            .string(forKey: UserDefaultsKeys.sessionRestorerActiveFilePath)
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
        WorkspaceWindowController.shared.open(urls: urls, activate: activeURL)
        return true
    }

    private static func restoredSnapshot() -> SessionSnapshot? {
        guard
            let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.sessionRestorerDocumentReferences)
        else {
            return nil
        }

        let decoder = JSONDecoder()

        guard
            let documentReferences = try? decoder.decode([RestorableDocumentReference].self, from: data)
        else {
            return nil
        }

        let activeDocumentReference = UserDefaults.standard.data(forKey: UserDefaultsKeys.sessionRestorerActiveDocumentReference)
            .flatMap { try? decoder.decode(RestorableDocumentReference.self, from: $0) }

        return SessionSnapshot(
            documentReferences: documentReferences,
            activeDocumentReference: activeDocumentReference
        )
    }

    private static func persist(_ snapshot: SessionSnapshot) {
        let encoder = JSONEncoder()

        if let documentData = try? encoder.encode(snapshot.documentReferences) {
            UserDefaults.standard.set(documentData, forKey: UserDefaultsKeys.sessionRestorerDocumentReferences)
        }

        if let activeDocumentReference = snapshot.activeDocumentReference,
           let activeData = try? encoder.encode(activeDocumentReference) {
            UserDefaults.standard.set(activeData, forKey: UserDefaultsKeys.sessionRestorerActiveDocumentReference)
        } else {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.sessionRestorerActiveDocumentReference)
        }

        let openFilePaths = snapshot.documentReferences.compactMap { reference -> String? in
            guard case let .file(path) = reference else { return nil }
            return path
        }
        let activeFilePath: String?
        if case let .file(path)? = snapshot.activeDocumentReference {
            activeFilePath = path
        } else {
            activeFilePath = nil
        }

        UserDefaults.standard.set(openFilePaths, forKey: UserDefaultsKeys.sessionRestorerOpenFilePaths)
        UserDefaults.standard.set(activeFilePath, forKey: UserDefaultsKeys.sessionRestorerActiveFilePath)
    }
}
