import AppKit
import XCTest
@testable import vmini

@MainActor
final class SidebarAndPersistenceTests: XCTestCase {
    func testFolderTreeProviderSortsDirectoriesBeforeFilesAndFiltersHiddenEntries() throws {
        let rootURL = try makeTemporaryDirectory(name: "tree-root")
        let visibleDirectory = rootURL.appendingPathComponent("Beta", isDirectory: true)
        let visiblePackage = rootURL.appendingPathComponent("Alpha.app", isDirectory: true)
        let visibleFile = rootURL.appendingPathComponent("gamma.txt")
        let hiddenFile = rootURL.appendingPathComponent(".secret")

        try FileManager.default.createDirectory(at: visibleDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: visiblePackage, withIntermediateDirectories: true)
        try "package".write(to: visiblePackage.appendingPathComponent("Contents.txt"), atomically: true, encoding: .utf8)
        try "file".write(to: visibleFile, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)

        let provider = FolderTreeProvider(fileManager: .default)
        let titles = provider.childNodes(for: rootURL).map(\.title)

        XCTAssertEqual(titles, ["Alpha.app", "Beta", "gamma.txt"])
    }

    func testFolderTreeProviderRefreshesNodeWhenFileBecomesDirectory() throws {
        let rootURL = try makeTemporaryDirectory(name: "file-to-directory")
        let replacedURL = rootURL.appendingPathComponent("Replaced")
        try "file".write(to: replacedURL, atomically: true, encoding: .utf8)

        let provider = FolderTreeProvider(fileManager: .default)
        let oldNode = try XCTUnwrap(provider.childNodes(for: rootURL).first)
        XCTAssertFalse(oldNode.isDirectory)

        try FileManager.default.removeItem(at: replacedURL)
        try FileManager.default.createDirectory(at: replacedURL, withIntermediateDirectories: false)

        let invalidatedPaths = provider.invalidateContents(at: [rootURL])
        let newNode = try XCTUnwrap(provider.childNodes(for: rootURL).first)

        XCTAssertTrue(invalidatedPaths.contains(replacedURL.path))
        XCTAssertFalse(newNode === oldNode)
        XCTAssertTrue(newNode.isDirectory)
    }

    func testFolderTreeProviderInvalidatesCachedDescendantsBeforeRemovingEdges() throws {
        let rootURL = try makeTemporaryDirectory(name: "tree-invalidation")
        let replacedURL = rootURL.appendingPathComponent("Folder", isDirectory: true)
        let oldChildURL = replacedURL.appendingPathComponent("old.txt")
        try FileManager.default.createDirectory(at: replacedURL, withIntermediateDirectories: false)
        try "old".write(to: oldChildURL, atomically: true, encoding: .utf8)

        let provider = FolderTreeProvider(fileManager: .default)
        let oldFolder = try XCTUnwrap(provider.childNodes(for: rootURL).first)
        let oldChild = try XCTUnwrap(oldFolder.children.first)

        try FileManager.default.removeItem(at: replacedURL)
        try FileManager.default.createDirectory(at: replacedURL, withIntermediateDirectories: false)
        let newChildURL = replacedURL.appendingPathComponent("new.txt")
        try "new".write(to: newChildURL, atomically: true, encoding: .utf8)

        let invalidatedPaths = provider.invalidateContents(at: [rootURL])
        let newFolder = try XCTUnwrap(provider.childNodes(for: rootURL).first)

        XCTAssertTrue(invalidatedPaths.contains(oldChildURL.path))
        XCTAssertFalse(newFolder === oldFolder)
        XCTAssertEqual(newFolder.children.map(\.title), ["new.txt"])
        XCTAssertFalse(newFolder.children.contains { $0 === oldChild })
    }

    func testFolderTreeNodeDoesNotKeepItsProviderAlive() throws {
        let rootURL = try makeTemporaryDirectory(name: "provider-lifetime")
        var provider: FolderTreeProvider? = FolderTreeProvider(fileManager: .default)
        let weakProvider = { [weak provider] in provider }
        let node = try XCTUnwrap(provider?.rootNodes(for: [rootURL]).first)

        provider = nil

        XCTAssertNil(weakProvider())
        XCTAssertTrue(node.children.isEmpty)
    }

    func testFolderSidebarExpansionControllerAvoidsRedundantExpansionCalls() {
        let rootURL = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let childURL = rootURL.appendingPathComponent("child", isDirectory: true)
        let provider = StubFolderProvider(tree: [rootURL: [childURL], childURL: []])
        let rootNode = FolderTreeNode(
            url: rootURL,
            title: rootURL.lastPathComponent,
            isDirectory: true,
            provider: provider
        )
        let childNode = rootNode.children[0]
        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SidebarAndPersistenceTests.Expansion"))
        let store = OpenFoldersStore(persistence: persistence)
        let outlineView = OutlineViewSpy()
        let controller = FolderSidebarExpansionController(outlineView: outlineView, store: store)

        store.setExpanded(true, for: rootURL)
        store.setExpanded(true, for: childURL)

        controller.applyExpansionState(to: [rootNode])
        controller.applyExpansionState(to: [rootNode])

        XCTAssertEqual(outlineView.expandCallIdentifiers.count, 2)
        XCTAssertEqual(outlineView.expandCallIdentifiers, [ObjectIdentifier(rootNode), ObjectIdentifier(childNode)])

        store.setExpanded(false, for: childURL)
        controller.applyExpansionState(to: [rootNode])

        XCTAssertEqual(outlineView.collapseCallIdentifiers, [ObjectIdentifier(childNode)])
    }

    func testFolderSidebarSelectionControllerOnlySelectsVisibleExpandedNodes() {
        let rootURL = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let childURL = rootURL.appendingPathComponent("child.txt")
        let provider = StubFolderProvider(tree: [rootURL: [childURL]])
        let rootNode = FolderTreeNode(
            url: rootURL,
            title: rootURL.lastPathComponent,
            isDirectory: true,
            provider: provider
        )
        let childNode = rootNode.children[0]
        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SidebarAndPersistenceTests.Selection"))
        let store = OpenFoldersStore(persistence: persistence)
        let outlineView = OutlineViewSpy()
        let controller = FolderSidebarSelectionController(outlineView: outlineView, store: store)

        outlineView.rowsByIdentifier[ObjectIdentifier(childNode)] = 4
        store.select(childURL)
        controller.applySelection(in: [rootNode])
        XCTAssertTrue(outlineView.didDeselectAll)

        outlineView.didDeselectAll = false
        outlineView.expandedIdentifiers.insert(ObjectIdentifier(rootNode))
        controller.applySelection(in: [rootNode])

        XCTAssertEqual(outlineView.recordedSelectedRowIndexes, IndexSet(integer: 4))
        XCTAssertFalse(outlineView.didDeselectAll)
    }

    func testWorkspacePersistenceRoundTripsStoredValues() throws {
        let userDefaults = makeUserDefaults(prefix: "SidebarAndPersistenceTests.Persistence")
        let persistence = WorkspacePersistence(userDefaults: userDefaults)
        let bookmarkURL = try makeTemporaryDirectory(name: "bookmark")
        let bookmarkData = try bookmarkURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let sessionData = try JSONEncoder().encode([RestorableDocumentReference.file(path: "/tmp/file.txt")])
        let activeData = try JSONEncoder().encode(RestorableDocumentReference.untitled(sessionID: UUID()))

        persistence.workspaceWindowFrame = "{{1, 2}, {3, 4}}"
        persistence.openFilesSidebarWidth = 320
        persistence.openFolderBookmarks = [bookmarkData]
        persistence.openFolderExpandedPaths = [bookmarkURL.path]
        persistence.sessionDocumentReferencesData = sessionData
        persistence.sessionActiveDocumentReferenceData = activeData
        persistence.syntaxLanguageOverrides = ["/tmp/file.txt": SyntaxLanguage.yaml.rawValue]

        XCTAssertEqual(persistence.workspaceWindowFrame, "{{1, 2}, {3, 4}}")
        XCTAssertEqual(persistence.openFilesSidebarWidth, 320, accuracy: 0.001)
        XCTAssertEqual(persistence.openFolderBookmarks, [bookmarkData])
        XCTAssertEqual(persistence.openFolderExpandedPaths, [bookmarkURL.path])
        XCTAssertEqual(persistence.sessionDocumentReferencesData, sessionData)
        XCTAssertEqual(persistence.sessionActiveDocumentReferenceData, activeData)
        XCTAssertEqual(persistence.syntaxLanguageOverrides["/tmp/file.txt"], SyntaxLanguage.yaml.rawValue)
    }

    func testOpenFoldersSidebarOutlineControllerOnlyShowsRemoveFolderForRootNodes() throws {
        let rootURL = try makeTemporaryDirectory(name: "menu-root")
        let childDirectoryURL = rootURL.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: childDirectoryURL, withIntermediateDirectories: true)

        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SidebarAndPersistenceTests.ContextMenu"))
        let store = OpenFoldersStore(persistence: persistence)
        let controller = OpenFoldersSidebarOutlineController(folderStore: store, treeProvider: FolderTreeProvider(fileManager: .default))
        let outlineView = OutlineViewSpy()
        let menu = NSMenu()

        controller.attach(to: outlineView)
        store.add([rootURL])
        controller.apply(
            state: OpenFoldersStore.State(
                folderURLs: store.folderURLs,
                selectedURL: store.selectedURL,
                expandedFolderPaths: [rootURL.path],
                contentVersion: 0,
                refreshedFolderPaths: []
            )
        )

        guard let rootNode = outlineView.stubbedItemsByRow[0] as? FolderTreeNode else {
            return XCTFail("Expected root node at row 0")
        }
        let childNode = rootNode.children[0]
        outlineView.stubbedItemsByRow[1] = childNode

        outlineView.stubbedClickedRow = 0
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.map(\.title), ["Remove Folder"])
        XCTAssertEqual(menu.items.first?.representedObject as? URL, rootURL)

        menu.removeAllItems()
        outlineView.stubbedClickedRow = 1
        controller.menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.isEmpty)
    }

    func testRemovingFolderEvictsItsCachedTree() throws {
        let rootURL = try makeTemporaryDirectory(name: "removed-root")
        let childURL = rootURL.appendingPathComponent("child.txt")
        try "child".write(to: childURL, atomically: true, encoding: .utf8)

        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SidebarAndPersistenceTests.RemovedRoot"))
        let store = OpenFoldersStore(persistence: persistence)
        let provider = FolderTreeProvider(fileManager: .default)
        let controller = OpenFoldersSidebarOutlineController(folderStore: store, treeProvider: provider)
        let outlineView = OutlineViewSpy()
        controller.attach(to: outlineView)
        store.add([rootURL])
        controller.apply(state: OpenFoldersStore.State(
            folderURLs: store.folderURLs,
            selectedURL: store.selectedURL,
            expandedFolderPaths: [rootURL.path],
            contentVersion: 0,
            refreshedFolderPaths: []
        ))

        weak var removedRoot: FolderTreeNode?
        weak var removedChild: FolderTreeNode?
        do {
            let rootNode = try XCTUnwrap(outlineView.stubbedItemsByRow[0] as? FolderTreeNode)
            removedRoot = rootNode
            removedChild = try XCTUnwrap(rootNode.children.first)
        }

        store.remove(rootURL)
        controller.apply(state: OpenFoldersStore.State(
            folderURLs: store.folderURLs,
            selectedURL: store.selectedURL,
            expandedFolderPaths: [],
            contentVersion: 0,
            refreshedFolderPaths: []
        ))

        XCTAssertNil(removedRoot)
        XCTAssertNil(removedChild)
    }

    func testSidebarFolderWatcherDropsPendingChangesFromAnObsoleteWatch() async throws {
        let oldDirectory = try makeTemporaryDirectory(name: "watch-old")
        let currentDirectory = try makeTemporaryDirectory(name: "watch-current")
        let watcher = SidebarFolderWatcher()
        defer { watcher.stop() }

        let obsoleteChange = expectation(description: "obsolete watcher callback")
        obsoleteChange.isInverted = true
        let currentChange = expectation(description: "current watcher callback")
        watcher.watch(directoryURLs: [oldDirectory]) { _ in
            obsoleteChange.fulfill()
        }
        try await Task.sleep(for: .milliseconds(100))
        try "old".write(
            to: oldDirectory.appendingPathComponent("change.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await Task.sleep(for: .milliseconds(100))

        watcher.watch(directoryURLs: [currentDirectory]) { changedURLs in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(changedURLs.map(\.standardizedFileURL.path), [currentDirectory.path])
            currentChange.fulfill()
        }
        try await Task.sleep(for: .milliseconds(100))
        try "current".write(
            to: currentDirectory.appendingPathComponent("change.txt"),
            atomically: true,
            encoding: .utf8
        )

        await fulfillment(of: [currentChange, obsoleteChange], timeout: 2)
    }

    func testOpenFoldersStoreRefreshContentsNotifiesObservers() async {
        let persistence = WorkspacePersistence(userDefaults: makeUserDefaults(prefix: "SidebarAndPersistenceTests.Refresh"))
        let store = OpenFoldersStore(persistence: persistence)
        let expectation = expectation(description: "refresh notification")
        var observedStates: [OpenFoldersStore.State] = []

        let token = store.observe { state in
            observedStates.append(state)
            if observedStates.count == 2 {
                expectation.fulfill()
            }
        }
        defer { token.cancel() }

        store.refreshContents(at: [])

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(observedStates.count, 2)
        XCTAssertEqual(observedStates[1].contentVersion, observedStates[0].contentVersion + 1)
        XCTAssertEqual(observedStates[1].folderURLs, observedStates[0].folderURLs)
        XCTAssertEqual(observedStates[1].expandedFolderPaths, observedStates[0].expandedFolderPaths)
    }

    private func makeTemporaryDirectory(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidebarAndPersistenceTests-\(name)-\(UUID().uuidString)", isDirectory: true)
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

private final class StubFolderProvider: FolderTreeProviding {
    private let tree: [URL: [URL]]

    init(tree: [URL: [URL]]) {
        self.tree = tree
    }

    func isDirectory(_ url: URL) -> Bool {
        tree[url] != nil
    }

    func childNodes(for url: URL) -> [FolderTreeNode] {
        (tree[url] ?? []).map { childURL in
            FolderTreeNode(
                url: childURL,
                title: childURL.lastPathComponent,
                isDirectory: tree[childURL] != nil,
                provider: self
            )
        }
    }
}

@MainActor
private final class OutlineViewSpy: NSOutlineView {
    var expandedIdentifiers: Set<ObjectIdentifier> = []
    var expandCallIdentifiers: [ObjectIdentifier] = []
    var collapseCallIdentifiers: [ObjectIdentifier] = []
    var rowsByIdentifier: [ObjectIdentifier: Int] = [:]
    var recordedSelectedRowIndexes = IndexSet()
    var didDeselectAll = false
    var stubbedItemsByRow: [Int: Any] = [:]
    var stubbedClickedRow = -1

    override var clickedRow: Int {
        stubbedClickedRow
    }

    override func reloadData() {
        super.reloadData()

        guard let dataSource else { return }

        stubbedItemsByRow.removeAll()
        rowsByIdentifier.removeAll()

        let rootCount = dataSource.outlineView!(self, numberOfChildrenOfItem: nil)
        for index in 0..<rootCount {
            let item = dataSource.outlineView!(self, child: index, ofItem: nil)
            stubbedItemsByRow[index] = item

            if let node = item as? FolderTreeNode {
                rowsByIdentifier[ObjectIdentifier(node)] = index
            }
        }
    }

    override func item(atRow row: Int) -> Any? {
        stubbedItemsByRow[row]
    }

    override func isItemExpanded(_ item: Any?) -> Bool {
        guard let node = item as? FolderTreeNode else { return false }
        return expandedIdentifiers.contains(ObjectIdentifier(node))
    }

    override func expandItem(_ item: Any?) {
        guard let node = item as? FolderTreeNode else { return }
        let identifier = ObjectIdentifier(node)
        expandedIdentifiers.insert(identifier)
        expandCallIdentifiers.append(identifier)
    }

    override func collapseItem(_ item: Any?) {
        guard let node = item as? FolderTreeNode else { return }
        let identifier = ObjectIdentifier(node)
        expandedIdentifiers.remove(identifier)
        collapseCallIdentifiers.append(identifier)
    }

    override func row(forItem item: Any?) -> Int {
        guard let node = item as? FolderTreeNode else { return -1 }
        return rowsByIdentifier[ObjectIdentifier(node)] ?? -1
    }

    override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        recordedSelectedRowIndexes = indexes
    }

    override func deselectAll(_ sender: Any?) {
        didDeselectAll = true
        recordedSelectedRowIndexes = []
    }
}
