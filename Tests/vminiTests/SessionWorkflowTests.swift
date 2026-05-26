import AppKit
import XCTest
@testable import vmini

@MainActor
final class SessionWorkflowTests: XCTestCase {
    func testSessionManagerPersistsMixedDocumentsAndRestoresActiveSelection() async throws {
        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SessionWorkflowTests.Session"))
        let store = OpenDocumentsStore()
        let router = RecordingDocumentRouter()
        let sessionManager = WorkspaceSessionManager(
            persistence: persistence,
            openDocumentsStore: store,
            documentRouter: router
        )
        let fileURL = try makeTemporaryFile(named: "notes.txt", contents: "hello")
        let fileDocument = makeDocument(store: store)
        let untitledDocument = makeDocument(store: store)

        fileDocument.fileURL = fileURL
        await Task.yield()

        store.register(untitledDocument)
        store.register(fileDocument, makeActive: true)

        sessionManager.saveOpenFiles()

        XCTAssertEqual(
            sessionManager.restoredDocumentReferences(),
            [
                .untitled(sessionID: untitledDocument.sessionIdentifier),
                .file(path: fileURL.standardizedFileURL.path)
            ]
        )
        XCTAssertEqual(
            sessionManager.restoredActiveDocumentReference(),
            .file(path: fileURL.standardizedFileURL.path)
        )

        XCTAssertTrue(sessionManager.reopenLastFiles())
        XCTAssertEqual(
            router.restoredReferences,
            [
                .untitled(sessionID: untitledDocument.sessionIdentifier),
                .file(path: fileURL.standardizedFileURL.path)
            ]
        )
        XCTAssertEqual(router.restoredActiveIdentifier, fileURL.standardizedFileURL.path)
    }

    func testSessionManagerPrepareForTerminationLocksSnapshotUntilCancellation() async throws {
        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SessionWorkflowTests.Termination"))
        let store = OpenDocumentsStore()
        let sessionManager = WorkspaceSessionManager(
            persistence: persistence,
            openDocumentsStore: store,
            documentRouter: RecordingDocumentRouter()
        )
        let firstFileURL = try makeTemporaryFile(named: "first.txt", contents: "one")
        let secondFileURL = try makeTemporaryFile(named: "second.txt", contents: "two")
        let firstDocument = makeDocument(store: store)
        let secondDocument = makeDocument(store: store)

        firstDocument.fileURL = firstFileURL
        await Task.yield()
        store.register(firstDocument, makeActive: true)
        sessionManager.prepareForTermination()

        secondDocument.fileURL = secondFileURL
        await Task.yield()
        store.register(secondDocument, makeActive: true)
        sessionManager.saveOpenFiles()

        XCTAssertEqual(
            sessionManager.restoredDocumentReferences(),
            [.file(path: firstFileURL.standardizedFileURL.path)]
        )

        sessionManager.cancelTermination()

        XCTAssertEqual(
            sessionManager.restoredDocumentReferences(),
            [
                .file(path: firstFileURL.standardizedFileURL.path),
                .file(path: secondFileURL.standardizedFileURL.path)
            ]
        )
        XCTAssertEqual(
            sessionManager.restoredActiveDocumentReference(),
            .file(path: secondFileURL.standardizedFileURL.path)
        )
    }

    func testSessionManagerPersistsDocumentOrderAfterReorder() async throws {
        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SessionWorkflowTests.Reorder"))
        let store = OpenDocumentsStore()
        let sessionManager = WorkspaceSessionManager(
            persistence: persistence,
            openDocumentsStore: store,
            documentRouter: RecordingDocumentRouter()
        )
        let fileURLs = try [
            makeTemporaryFile(named: "a.txt", contents: "a"),
            makeTemporaryFile(named: "b.txt", contents: "b"),
            makeTemporaryFile(named: "c.txt", contents: "c")
        ]
        let documents = fileURLs.map { _ in makeDocument(store: store) }

        for (document, fileURL) in zip(documents, fileURLs) {
            document.fileURL = fileURL
            await Task.yield()
            store.register(document)
        }

        store.reorder(document: documents[0], to: 2)
        sessionManager.saveOpenFiles()

        XCTAssertEqual(
            sessionManager.restoredDocumentReferences(),
            [
                .file(path: fileURLs[1].standardizedFileURL.path),
                .file(path: fileURLs[2].standardizedFileURL.path),
                .file(path: fileURLs[0].standardizedFileURL.path)
            ]
        )
    }

    func testWorkspaceDocumentOpenerSetsFileURLFileTypeAndTextForOpenedFiles() throws {
        let documentController = DocumentController()
        let store = OpenDocumentsStore()
        let opener = WorkspaceDocumentOpener(documentController: documentController, openDocumentsStore: store)
        let fileURL = try makeTemporaryFile(named: "open.txt", contents: "hello world")
        var presentedDocument: Document?

        opener.open(
            [fileURL],
            activate: fileURL,
            fallbackDocument: nil,
            presentDocument: { presentedDocument = $0 },
            noDocumentFallback: { XCTFail("Expected document to open") }
        )

        let document = try XCTUnwrap(presentedDocument)
        let editorViewController = document.editorViewController(onFileSystemURLsDropped: { _ in })
        XCTAssertEqual(document.fileURL?.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(editorViewController.text, "hello world")
        let typeIdentifier = try XCTUnwrap(document.fileType)
        XCTAssertTrue(Document.supportedTypes.contains { typeIdentifier == $0.identifier })
        XCTAssertTrue(store.activeDocument === document)
    }

    func testWorkspaceDocumentCoordinatorReopensMostRecentClosedFileDocument() async throws {
        let history = ClosedDocumentHistory()
        let store = OpenDocumentsStore()
        let documentController = DocumentController()
        let opener = WorkspaceDocumentOpener(documentController: documentController, openDocumentsStore: store)
        let coordinator = WorkspaceDocumentCoordinator(
            documentOpener: opener,
            openDocumentsStore: store,
            closedDocumentHistory: history,
            documentController: documentController
        )
        let fileURL = try makeTemporaryFile(named: "closed.txt", contents: "restored")
        let document = makeDocument(store: store)

        document.fileURL = fileURL
        await Task.yield()
        history.record(document: document)

        coordinator.reopenMostRecentClosedDocument()

        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(store.activeDocument?.fileURL?.standardizedFileURL, fileURL.standardizedFileURL)
    }

    func testWorkspaceDocumentCoordinatorReopensMostRecentClosedUntitledDocument() {
        let history = ClosedDocumentHistory()
        let store = OpenDocumentsStore()
        let documentController = DocumentController()
        let opener = WorkspaceDocumentOpener(documentController: documentController, openDocumentsStore: store)
        let coordinator = WorkspaceDocumentCoordinator(
            documentOpener: opener,
            openDocumentsStore: store,
            closedDocumentHistory: history,
            documentController: documentController
        )
        let sessionIdentifier = UUID()
        let document = makeDocument(store: store, sessionIdentifier: sessionIdentifier)

        history.record(document: document)
        coordinator.reopenMostRecentClosedDocument()

        XCTAssertEqual(store.documents.count, 1)
        XCTAssertNil(store.activeDocument?.fileURL)
        XCTAssertEqual(store.activeDocument?.sessionIdentifier, sessionIdentifier)
    }

    func testSyntaxOverrideMigratesFromUntitledDocumentToSavedFileIdentifier() async throws {
        let userDefaults = makeUserDefaults(prefix: "SessionWorkflowTests.SyntaxMigration")
        let syntaxOverrideStore = SyntaxOverrideStore(userDefaults: userDefaults)
        let store = OpenDocumentsStore()
        let document = Document(
            sessionIdentifier: UUID(),
            syntaxOverrideStore: syntaxOverrideStore,
            openDocumentsStore: store
        )
        let fileURL = try makeTemporaryFile(named: "override.json", contents: "{}")

        document.setSyntaxLanguageOverride(.yaml)
        XCTAssertTrue(userDefaults.dictionary(forKey: UserDefaultsKeys.syntaxLanguageOverrides)?.isEmpty ?? true)

        document.fileURL = fileURL
        await Task.yield()

        XCTAssertEqual(
            syntaxOverrideStore.override(for: fileURL.standardizedFileURL.path),
            .yaml
        )
        XCTAssertEqual(
            userDefaults.dictionary(forKey: UserDefaultsKeys.syntaxLanguageOverrides)?.count,
            1
        )
    }

    func testDocumentClosesWhenFileURLMovesIntoTrash() async throws {
        let store = OpenDocumentsStore()
        let document = makeDocument(store: store)
        let fileURL = try makeTemporaryFile(named: "trash-me.txt", contents: "bye")
        let trashURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".Trash", isDirectory: true)
            .appendingPathComponent(fileURL.lastPathComponent)

        document.fileURL = fileURL
        await Task.yield()
        store.register(document, makeActive: true)

        document.fileURL = trashURL
        await Task.yield()

        XCTAssertFalse(store.contains(document))
        XCTAssertNil(store.activeDocument)
    }

    private func makeDocument(
        store: OpenDocumentsStore,
        sessionIdentifier: UUID = UUID()
    ) -> Document {
        Document(
            sessionIdentifier: sessionIdentifier,
            syntaxOverrideStore: SyntaxOverrideStore(userDefaults: makeUserDefaults(prefix: "SessionWorkflowTests.Syntax")),
            openDocumentsStore: store
        )
    }

    private func makeTemporaryFile(named name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        return url
    }

    private func makeUserDefaults(prefix: String) -> UserDefaults {
        let suiteName = "\(prefix).\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return userDefaults
    }
}

@MainActor
private final class RecordingDocumentRouter: WorkspaceDocumentRouting {
    private(set) var restoredReferences: [RestorableDocumentReference] = []
    private(set) var restoredActiveIdentifier: String?

    func present(document: Document) {}
    func open(urls: [URL], activate activeURL: URL?) {}
    func createUntitledDocument() {}
    func createUntitledDocument(sessionIdentifier: UUID) {}

    func restoreSession(_ references: [RestorableDocumentReference], activate activeIdentifier: String?) -> Bool {
        restoredReferences = references
        restoredActiveIdentifier = activeIdentifier
        return !references.isEmpty
    }

    func closeCurrentDocument() {}
    func close(document: Document) {}
    func reopenMostRecentClosedDocument() {}
}
