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

        let didRestore = await sessionManager.reopenLastFiles()
        XCTAssertTrue(didRestore)
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

    func testSessionManagerRefreshTerminationSnapshotIfNeededUpdatesSavedFileReferenceWhileLocked() async throws {
        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SessionWorkflowTests.TerminationRefresh"))
        let store = OpenDocumentsStore()
        let sessionManager = WorkspaceSessionManager(
            persistence: persistence,
            openDocumentsStore: store,
            documentRouter: RecordingDocumentRouter()
        )
        let fileURL = try makeTemporaryFile(named: "saved-on-quit.txt", contents: "saved")
        let document = makeDocument(store: store)

        store.register(document, makeActive: true)
        sessionManager.prepareForTermination()
        XCTAssertEqual(sessionManager.restoredDocumentReferences(), [.untitled(sessionID: document.sessionIdentifier)])

        document.fileURL = fileURL
        await Task.yield()
        sessionManager.refreshTerminationSnapshotIfNeeded()

        XCTAssertEqual(sessionManager.restoredDocumentReferences(), [.file(path: fileURL.standardizedFileURL.path)])
        XCTAssertEqual(sessionManager.restoredActiveDocumentReference(), .file(path: fileURL.standardizedFileURL.path))

        store.unregister(document)
        XCTAssertEqual(sessionManager.restoredDocumentReferences(), [.file(path: fileURL.standardizedFileURL.path)])
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

    func testWorkspaceDocumentOpenerSetsFileURLFileTypeAndTextForOpenedFiles() async throws {
        let documentController = DocumentController()
        let store = OpenDocumentsStore()
        let opener = WorkspaceDocumentOpener(documentController: documentController, openDocumentsStore: store)
        let fileURL = try makeTemporaryFile(named: "open.txt", contents: "hello world")
        var presentedDocument: Document?

        let failures = await opener.openInBackground(
            [fileURL],
            activate: fileURL,
            fallbackDocument: nil,
            presentDocument: {
                presentedDocument = $0
                store.select($0)
            },
            noDocumentFallback: { XCTFail("Expected document to open") }
        )

        XCTAssertTrue(failures.isEmpty)
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
        for _ in 0..<20 where store.documents.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(store.activeDocument?.fileURL?.standardizedFileURL, fileURL.standardizedFileURL)
    }

    func testSlowEarlierOpenDoesNotOverrideNewerOpenSelection() async throws {
        let slowURL = try makeTemporaryFile(named: "slow-open.txt", contents: "slow")
        let fastURL = try makeTemporaryFile(named: "fast-open.txt", contents: "fast")
        let history = ClosedDocumentHistory()
        let store = OpenDocumentsStore()
        let documentController = DocumentController()
        let opener = WorkspaceDocumentOpener(
            documentController: documentController,
            openDocumentsStore: store,
            payloadLoader: { url in
                if url.standardizedFileURL == slowURL.standardizedFileURL {
                    try await Task.sleep(for: .milliseconds(250))
                }
                return try await DocumentPayloadLoader.load(from: url)
            }
        )
        let coordinator = WorkspaceDocumentCoordinator(
            documentOpener: opener,
            openDocumentsStore: store,
            closedDocumentHistory: history,
            documentController: documentController
        )

        coordinator.open(urls: [slowURL], activate: slowURL)
        try await Task.sleep(for: .milliseconds(20))
        coordinator.open(urls: [fastURL], activate: fastURL)

        for _ in 0..<40 where store.documents.count < 2 {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(store.documents.count, 2)
        XCTAssertEqual(store.activeDocument?.fileURL?.standardizedFileURL, fastURL.standardizedFileURL)
    }

    func testStaleOpenDoesNotSelectWhileNewerRequestIsStillLoading() async throws {
        let earlierURL = try makeTemporaryFile(named: "earlier-open.txt", contents: "earlier")
        let newerURL = try makeTemporaryFile(named: "newer-open.txt", contents: "newer")
        let history = ClosedDocumentHistory()
        let store = OpenDocumentsStore()
        let documentController = DocumentController()
        let opener = WorkspaceDocumentOpener(
            documentController: documentController,
            openDocumentsStore: store,
            payloadLoader: { url in
                let delay = url.standardizedFileURL == earlierURL.standardizedFileURL ? 60 : 400
                try await Task.sleep(for: .milliseconds(delay))
                return try await DocumentPayloadLoader.load(from: url)
            }
        )
        let coordinator = WorkspaceDocumentCoordinator(
            documentOpener: opener,
            openDocumentsStore: store,
            closedDocumentHistory: history,
            documentController: documentController
        )

        coordinator.open(urls: [earlierURL], activate: earlierURL)
        try await Task.sleep(for: .milliseconds(20))
        coordinator.open(urls: [newerURL], activate: newerURL)

        for _ in 0..<30 where !store.documents.contains(where: { $0.fileURL?.standardizedFileURL == earlierURL.standardizedFileURL }) {
            try await Task.sleep(for: .milliseconds(15))
        }

        XCTAssertEqual(store.documents.count, 1)
        XCTAssertNil(store.activeDocument)

        for _ in 0..<40 where store.documents.count < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(store.documents.count, 2)
        XCTAssertEqual(store.activeDocument?.fileURL?.standardizedFileURL, newerURL.standardizedFileURL)
    }

    func testSelectingAnAlreadyOpenTabInvalidatesPendingOpenSelection() async throws {
        let existingURL = try makeTemporaryFile(named: "already-open.txt", contents: "existing")
        let slowURL = try makeTemporaryFile(named: "select-during-open.txt", contents: "new")
        let history = ClosedDocumentHistory()
        let store = OpenDocumentsStore()
        let documentController = DocumentController()
        let opener = WorkspaceDocumentOpener(
            documentController: documentController,
            openDocumentsStore: store,
            payloadLoader: { url in
                try await Task.sleep(for: .milliseconds(150))
                return try await DocumentPayloadLoader.load(from: url)
            }
        )
        let coordinator = WorkspaceDocumentCoordinator(
            documentOpener: opener,
            openDocumentsStore: store,
            closedDocumentHistory: history,
            documentController: documentController
        )
        let existingDocument = Document()
        existingDocument.fileURL = existingURL
        store.register(existingDocument, makeActive: true)

        coordinator.open(urls: [slowURL], activate: slowURL)
        try await Task.sleep(for: .milliseconds(20))
        coordinator.present(document: existingDocument)

        for _ in 0..<30 where store.documents.count < 2 {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(store.documents.count, 2)
        XCTAssertTrue(store.activeDocument === existingDocument)
    }

    func testWorkspaceDocumentOpenerRestoresActiveFileFirstAndKeepsSavedOrder() async throws {
        let firstURL = try makeTemporaryFile(named: "restore-first.txt", contents: "first")
        let activeURL = try makeTemporaryFile(named: "restore-active.txt", contents: "active")
        let lastURL = try makeTemporaryFile(named: "restore-last.txt", contents: "last")
        let references: [RestorableDocumentReference] = [
            .file(path: firstURL.path),
            .file(path: activeURL.path),
            .file(path: lastURL.path)
        ]
        let store = OpenDocumentsStore()
        let opener = WorkspaceDocumentOpener(
            documentController: DocumentController(),
            openDocumentsStore: store,
            payloadLoader: { url in
                if url.standardizedFileURL != activeURL.standardizedFileURL {
                    try await Task.sleep(for: .milliseconds(50))
                }
                return try await DocumentPayloadLoader.load(from: url)
            }
        )
        var presentedDocuments: [Document] = []
        var documentCountWhenActivePresented: Int?

        let result = await opener.restoreSession(
            references,
            activate: activeURL.path,
            presentDocument: { document in
                if presentedDocuments.isEmpty {
                    documentCountWhenActivePresented = store.documents.count
                }
                presentedDocuments.append(document)
                store.select(document)
            },
            noDocumentFallback: { XCTFail("Expected restored documents") }
        )

        XCTAssertTrue(result.didRestore)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(documentCountWhenActivePresented, 1)
        XCTAssertEqual(store.documents.compactMap { $0.fileURL?.standardizedFileURL }, [
            firstURL.standardizedFileURL,
            activeURL.standardizedFileURL,
            lastURL.standardizedFileURL
        ])
        XCTAssertEqual(store.activeDocument?.fileURL?.standardizedFileURL, activeURL.standardizedFileURL)
        XCTAssertEqual(presentedDocuments.first?.fileURL?.standardizedFileURL, activeURL.standardizedFileURL)
    }

    func testWorkspaceDocumentOpenerReturnsFailuresForMissingFiles() async throws {
        let missingURL = URL(fileURLWithPath: "/tmp/vmini-missing-\(UUID().uuidString).txt")
        let opener = WorkspaceDocumentOpener(documentController: DocumentController(), openDocumentsStore: OpenDocumentsStore())
        var didUseFallback = false

        let failures = await opener.openInBackground(
            [missingURL],
            activate: missingURL,
            fallbackDocument: nil,
            presentDocument: { _ in XCTFail("Expected open failure") },
            noDocumentFallback: { didUseFallback = true }
        )

        XCTAssertTrue(didUseFallback)
        XCTAssertEqual(failures.map(\.url), [missingURL.standardizedFileURL])
        XCTAssertFalse(failures.first?.message.isEmpty ?? true)
    }

    func testExternalReloadDiscardsPayloadWhenDocumentRevisionChanges() async throws {
        let fileURL = try makeTemporaryFile(named: "revision-check.txt", contents: "disk")
        let store = OpenDocumentsStore()
        let lifecycle = DocumentFileLifecycleController(
            externalChangeCoordinator: DocumentExternalChangeCoordinator(),
            openDocumentsStore: store,
            payloadLoader: { url in
                try await Task.sleep(for: .milliseconds(100))
                return DocumentPayload(url: url, typeName: "public.plain-text", text: "disk version")
            }
        )
        var revision: UInt64 = 1
        var didInstallPayload = false
        var didPromptForConflict = false
        let reload = Task {
            await lifecycle.reloadFromDiskAfterExternalChange(
                fileURL: fileURL,
                currentFileURL: { fileURL },
                contentRevision: { revision },
                startingRevision: revision,
                restartWatcher: false,
                isDocumentEdited: false,
                isDocumentCurrentlyEdited: { true },
                reloadEvenIfEdited: false,
                installPayload: { _ in didInstallPayload = true },
                onReload: {},
                onMissingFile: { XCTFail("File exists") },
                onMissingFileWithUnsavedChanges: { XCTFail("File exists") },
                onExternalChangeWithUnsavedChanges: { _ in didPromptForConflict = true },
                onExternalChangeReload: { _ in }
            )
        }

        try await Task.sleep(for: .milliseconds(20))
        revision += 1
        await reload.value

        XCTAssertFalse(didInstallPayload)
        XCTAssertTrue(didPromptForConflict)
    }

    func testExternalReloadOrderingAndLifecycleInvalidation() async throws {
        let fileURL = try makeTemporaryFile(named: "overlapping-reloads.txt", contents: "disk")
        for newestFinishesFirst in [false, true] {
            let started = (0..<3).map { expectation(description: "reload \($0) started") }
            var continuations: [CheckedContinuation<DocumentPayload, Error>] = []
            var revision: UInt64 = 0
            var installed = "original"
            let lifecycle = DocumentFileLifecycleController(
                externalChangeCoordinator: DocumentExternalChangeCoordinator(),
                openDocumentsStore: OpenDocumentsStore(),
                payloadLoader: { _ in
                    try await withCheckedThrowingContinuation { continuation in
                        continuations.append(continuation)
                        started[continuations.count - 1].fulfill()
                    }
                }
            )
            func reload() async {
                await lifecycle.reloadFromDiskAfterExternalChange(
                    fileURL: fileURL, currentFileURL: { fileURL },
                    contentRevision: { revision }, startingRevision: revision,
                    restartWatcher: false, isDocumentEdited: false,
                    isDocumentCurrentlyEdited: { false }, reloadEvenIfEdited: false,
                    installPayload: { installed = $0.text; revision += 1 }, onReload: {},
                    onMissingFile: { XCTFail("File exists") },
                    onMissingFileWithUnsavedChanges: { XCTFail("File exists") },
                    onExternalChangeWithUnsavedChanges: { _ in XCTFail("No local edits") },
                    onExternalChangeReload: { _ in }
                )
            }
            let first = Task { await reload() }
            await fulfillment(of: [started[0]], timeout: 2)
            let second = Task { await reload() }
            await fulfillment(of: [started[1]], timeout: 2)
            let tasks = [first, second]
            for index in newestFinishesFirst ? [1, 0] : [0, 1] {
                continuations[index].resume(returning: DocumentPayload(
                    url: fileURL, typeName: "public.plain-text", text: "version \(index + 1)"
                ))
                await tasks[index].value
            }
            XCTAssertEqual(installed, "version 2")
            XCTAssertEqual(revision, 1, "Only the latest request should install a payload")

            let obsolete = Task { await reload() }
            await fulfillment(of: [started[2]], timeout: 2)
            if newestFinishesFirst {
                lifecycle.handleClose()
            } else {
                lifecycle.prepareForSave()
            }
            continuations[2].resume(returning: DocumentPayload(
                url: fileURL, typeName: "public.plain-text", text: "obsolete"
            ))
            await obsolete.value
            XCTAssertEqual(installed, "version 2", "Closing or saving must invalidate pending reads")
        }
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

    func testSessionManagerPersistsSavedFileReferenceForFormerlyUntitledDocumentBeforeTermination() async throws {
        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SessionWorkflowTests.SaveOnQuit"))
        let store = OpenDocumentsStore()
        let sessionManager = WorkspaceSessionManager(
            persistence: persistence,
            openDocumentsStore: store,
            documentRouter: RecordingDocumentRouter()
        )
        let document = makeDocument(store: store)
        let fileURL = try makeTemporaryFile(named: "saved-on-quit.txt", contents: "saved")

        store.register(document, makeActive: true)
        sessionManager.saveOpenFiles()
        XCTAssertEqual(sessionManager.restoredDocumentReferences(), [.untitled(sessionID: document.sessionIdentifier)])

        document.fileURL = fileURL
        await Task.yield()

        sessionManager.prepareForTermination()

        XCTAssertEqual(sessionManager.restoredDocumentReferences(), [.file(path: fileURL.standardizedFileURL.path)])
        XCTAssertEqual(sessionManager.restoredActiveDocumentReference(), .file(path: fileURL.standardizedFileURL.path))
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

    func restoreSession(_ references: [RestorableDocumentReference], activate activeIdentifier: String?) async -> Bool {
        restoredReferences = references
        restoredActiveIdentifier = activeIdentifier
        return !references.isEmpty
    }

    func closeCurrentDocument() {}
    func close(document: Document) {}
    func reopenMostRecentClosedDocument() {}
}
