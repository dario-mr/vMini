import AppKit
import XCTest
@testable import vmini

@MainActor
final class WorkspaceStateTests: XCTestCase {
    func testPreviewReusesItsPositionAndNotifiesOnceWithoutClosingKeptTabs() {
        let store = OpenDocumentsStore()
        let kept = makeDocument(openDocumentsStore: store)
        let first = makeDocument(openDocumentsStore: store)
        let second = makeDocument(openDocumentsStore: store)
        let last = makeDocument(openDocumentsStore: store)
        store.register(kept)
        store.registerPreview(first)
        store.register(last)
        var observedStates: [OpenDocumentsStore.State] = []
        let token = store.observe { observedStates.append($0) }
        defer { _ = token }

        store.registerPreview(second)

        XCTAssertEqual(store.documents.map(ObjectIdentifier.init), [kept, second, last].map(ObjectIdentifier.init))
        XCTAssertTrue(store.activeDocument === second)
        XCTAssertTrue(second.isPreview)
        XCTAssertFalse(first.isPreview)
        XCTAssertEqual(observedStates.count, 2)
        XCTAssertEqual(observedStates.last?.documents.count, 3)

        store.registerPreview(kept)
        XCTAssertTrue(store.activeDocument === kept)
        XCTAssertFalse(kept.isPreview)
        XCTAssertTrue(store.previewDocument === second)
    }

    func testEditingPreviewKeepsItOpenAfterUndoAndBrowsing() {
        let store = OpenDocumentsStore()
        let edited = makeDocument(openDocumentsStore: store)
        let next = makeDocument(openDocumentsStore: store)
        store.registerPreview(edited)
        let editor = edited.editorViewController(onFileSystemURLsDropped: { _ in })
        editor.text = "edited content"
        editor.onTextChanged?()

        XCTAssertTrue(edited.isDocumentEdited)
        XCTAssertFalse(edited.isPreview)
        edited.updateChangeCount(.changeUndone)
        store.registerPreview(next)

        XCTAssertEqual(store.documents.count, 2)
        XCTAssertTrue(store.contains(edited))
        XCTAssertEqual(editor.text, "edited content")
        XCTAssertTrue(next.isPreview)
    }

    func testKeepingAndPinningPreviewsPreventsReplacementAndClosingClearsPreview() {
        let store = OpenDocumentsStore(persistence: WorkspacePersistence(
            userDefaults: makeUserDefaults(prefix: "WorkspaceStateTests.PreviewPin")
        ))
        let kept = makeDocument(openDocumentsStore: store)
        let pinned = makeDocument(openDocumentsStore: store)
        let preview = makeDocument(openDocumentsStore: store)
        store.registerPreview(kept)
        kept.keepOpen()
        store.registerPreview(pinned)
        store.togglePinned(pinned)
        store.registerPreview(preview)

        XCTAssertEqual(store.documents.count, 3)
        XCTAssertFalse(kept.isPreview)
        XCTAssertFalse(pinned.isPreview)
        XCTAssertTrue(store.isPinned(pinned))
        XCTAssertTrue(preview.isPreview)
        preview.close()
        XCTAssertNil(store.previewDocument)
        XCTAssertEqual(store.documents.count, 2)
    }

    func testPreviewTabUsesItalicUntilDoubleClickKeepsItOpen() throws {
        let store = OpenDocumentsStore()
        let document = makeDocument(openDocumentsStore: store)
        store.registerPreview(document)
        let tab = DocumentTabView()
        tab.configure(document: document, isActive: true, isPinned: false)
        let title = try XCTUnwrap(tab.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertTrue(try XCTUnwrap(title.font).fontDescriptor.symbolicTraits.contains(.italic))

        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        tab.mouseDown(with: click)
        XCTAssertTrue(document.isPreview)

        let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 2, pressure: 1
        ))
        tab.mouseDown(with: doubleClick)
        tab.configure(document: document, isActive: true, isPinned: false)
        XCTAssertFalse(document.isPreview)
        XCTAssertFalse(try XCTUnwrap(title.font).fontDescriptor.symbolicTraits.contains(.italic))

        store.registerPreview(document)
        XCTAssertFalse(document.isPreview)
    }

    func testOpenDocumentsStoreBatchUpdateCoalescesObserverNotifications() {
        let store = OpenDocumentsStore()
        let documentA = makeDocument(openDocumentsStore: store)
        let documentB = makeDocument(openDocumentsStore: store)
        var observedStates: [OpenDocumentsStore.State] = []

        let token = store.observe { state in
            observedStates.append(state)
        }
        defer { _ = token }

        store.performBatchUpdate {
            store.register(documentA)
            store.register(documentB, makeActive: true)
        }

        XCTAssertEqual(observedStates.count, 2)
        XCTAssertEqual(observedStates[0].documents.count, 0)
        XCTAssertEqual(observedStates[1].documents.count, 2)
        XCTAssertTrue(observedStates[1].documents[0] === documentA)
        XCTAssertTrue(observedStates[1].documents[1] === documentB)
        XCTAssertTrue(observedStates[1].activeDocument === documentB)
    }

    func testOpenDocumentsStoreSelectsPreviousDocumentWhenActiveDocumentCloses() {
        let store = OpenDocumentsStore()
        let documentA = makeDocument(openDocumentsStore: store)
        let documentB = makeDocument(openDocumentsStore: store)
        let documentC = makeDocument(openDocumentsStore: store)

        store.register(documentA)
        store.register(documentB)
        store.register(documentC, makeActive: true)

        store.unregister(documentC)

        XCTAssertEqual(store.documents.count, 2)
        XCTAssertTrue(store.activeDocument === documentB)
    }

    func testPinnedTabsStayLeftAndPersistAcrossStoreRecreation() {
        let persistence = WorkspacePersistence(
            userDefaults: makeUserDefaults(prefix: "WorkspaceStateTests.PinnedTabs")
        )
        let store = OpenDocumentsStore(persistence: persistence)
        let pinnedAID = UUID()
        let pinnedBID = UUID()
        let unpinnedID = UUID()
        let pinnedA = makeDocument(openDocumentsStore: store, sessionIdentifier: pinnedAID)
        let pinnedB = makeDocument(openDocumentsStore: store, sessionIdentifier: pinnedBID)
        let unpinned = makeDocument(openDocumentsStore: store, sessionIdentifier: unpinnedID)

        store.register(unpinned)
        store.register(pinnedA)
        store.register(pinnedB)
        store.togglePinned(pinnedA)
        store.togglePinned(pinnedB)
        store.reorder(document: unpinned, to: 0)
        store.reorder(document: pinnedB, to: 0)

        XCTAssertEqual(store.documents.map(ObjectIdentifier.init), [
            ObjectIdentifier(pinnedB), ObjectIdentifier(pinnedA), ObjectIdentifier(unpinned),
        ])

        let restoredStore = OpenDocumentsStore(persistence: persistence)
        let restoredB = makeDocument(openDocumentsStore: restoredStore, sessionIdentifier: pinnedBID)
        let restoredA = makeDocument(openDocumentsStore: restoredStore, sessionIdentifier: pinnedAID)
        let restoredUnpinned = makeDocument(openDocumentsStore: restoredStore, sessionIdentifier: unpinnedID)
        restoredStore.register(restoredB)
        restoredStore.register(restoredA)
        restoredStore.register(restoredUnpinned)

        XCTAssertTrue(restoredStore.isPinned(restoredA))
        XCTAssertTrue(restoredStore.isPinned(restoredB))
        XCTAssertFalse(restoredStore.isPinned(restoredUnpinned))
        XCTAssertEqual(restoredStore.documents.map(ObjectIdentifier.init), [
            ObjectIdentifier(restoredB), ObjectIdentifier(restoredA), ObjectIdentifier(restoredUnpinned),
        ])
    }

    func testOpenFoldersStoreRestoresBookmarksAndExpandedStateFromPersistence() throws {
        let userDefaults = makeUserDefaults(prefix: "WorkspaceStateTests.Persistence")
        let persistence = WorkspacePersistence(userDefaults: userDefaults)
        let rootURL = try makeTemporaryDirectory(name: "root")
        let nestedURL = rootURL.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        persistence.openFolderBookmarks = [
            try rootURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        ]
        persistence.openFolderExpandedPaths = [rootURL.path, nestedURL.path]

        let store = OpenFoldersStore(persistence: persistence)

        XCTAssertEqual(store.folderURLs, [rootURL.standardizedFileURL])
        XCTAssertTrue(store.isExpanded(rootURL))
        XCTAssertTrue(store.isExpanded(nestedURL))
    }

    func testOpenFoldersStoreRemovingRootClearsDescendantSelectionAndExpansion() async throws {
        let userDefaults = makeUserDefaults(prefix: "WorkspaceStateTests.RemoveRoot")
        let persistence = WorkspacePersistence(userDefaults: userDefaults)
        let store = OpenFoldersStore(persistence: persistence)
        let rootURL = try makeTemporaryDirectory(name: "root")
        let nestedURL = rootURL.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)

        store.add([rootURL])
        store.select(nestedURL)
        store.setExpanded(true, for: nestedURL)
        await Task.yield()

        store.remove(rootURL)
        await Task.yield()

        XCTAssertTrue(store.folderURLs.isEmpty)
        XCTAssertNil(store.selectedURL)
        XCTAssertFalse(store.isExpanded(rootURL))
        XCTAssertFalse(store.isExpanded(nestedURL))
        XCTAssertTrue(persistence.openFolderBookmarks.isEmpty)
        XCTAssertTrue(persistence.openFolderExpandedPaths.isEmpty)
    }

    func testOpenFoldersStoreCoalescesSynchronousObserverNotifications() async throws {
        let userDefaults = makeUserDefaults(prefix: "WorkspaceStateTests.Observers")
        let persistence = WorkspacePersistence(userDefaults: userDefaults)
        let store = OpenFoldersStore(persistence: persistence)
        let rootURL = try makeTemporaryDirectory(name: "root")
        var observedStates: [OpenFoldersStore.State] = []

        let token = store.observe { state in
            observedStates.append(state)
        }
        defer { _ = token }

        store.add([rootURL])
        store.select(rootURL)
        await Task.yield()

        XCTAssertEqual(observedStates.count, 2)
        XCTAssertEqual(
            observedStates[0],
            .init(
                folderURLs: [],
                selectedURL: nil,
                expandedFolderPaths: [],
                contentVersion: 0,
                refreshedFolderPaths: []
            )
        )
        XCTAssertEqual(observedStates[1].folderURLs, [rootURL.standardizedFileURL])
        XCTAssertEqual(observedStates[1].selectedURL, rootURL.standardizedFileURL)
        XCTAssertEqual(observedStates[1].expandedFolderPaths, [rootURL.standardizedFileURL.path])
    }

    private func makeDocument(
        openDocumentsStore: OpenDocumentsStore,
        sessionIdentifier: UUID = UUID()
    ) -> Document {
        Document(
            sessionIdentifier: sessionIdentifier,
            syntaxOverrideStore: SyntaxOverrideStore(userDefaults: makeUserDefaults(prefix: "WorkspaceStateTests.Syntax")),
            openDocumentsStore: openDocumentsStore
        )
    }

    private func makeTemporaryDirectory(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceStateTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
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
