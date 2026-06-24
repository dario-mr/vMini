import AppKit
import XCTest
@testable import vmini

@MainActor
final class WorkspaceStateTests: XCTestCase {
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

    private func makeDocument(openDocumentsStore: OpenDocumentsStore) -> Document {
        Document(
            sessionIdentifier: UUID(),
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
