import AppKit
import DuckDB
import XCTest
@testable import vmini

@MainActor
final class ParquetViewerTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/scalars.snappy.parquet")
    }

    func testMixedTabsDuplicateOpenRestoreAndWritesLeaveFixtureUnchanged() async throws {
        try await checkWorkspace(parquetURLs: [fixture])
    }

    func testSuppliedSamplesInMixedWorkspace() async throws {
        guard let paths = ProcessInfo.processInfo.environment["VMINI_PARQUET_SAMPLES"] else {
            throw XCTSkip("Set VMINI_PARQUET_SAMPLES to colon-separated sample paths for acceptance validation.")
        }
        try await checkWorkspace(parquetURLs: paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
    }

    func testPageBoundEmptySchemaAndReadOnlyCellDisplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try Database(store: .inMemory)
        let connection = try database.connect()
        for count in [0, 1_001] {
            let url = directory.appendingPathComponent("\(count).parquet")
            try connection.execute("COPY (SELECT i AS id FROM range(\(count)) t(i)) TO '\(url.path)' (FORMAT PARQUET)")
            let session = ParquetSession(url: url)
            defer { session.close() }
            let page = try await loadedPage(session)
            XCTAssertEqual(page.rows.count, min(count, 1_000))
            XCTAssertEqual(page.totalRows, Int64(count))
            XCTAssertEqual(page.columns.first?.name, "id")
        }

        let session = ParquetSession(url: fixture)
        defer { session.close() }
        let page = try await loadedPage(session)
        XCTAssertEqual(page.columns[2].type, "DECIMAL(20,4)")
        XCTAssertEqual(page.rows[1][2], "90071992547409.1234")
        let viewer = ParquetViewController(session: session)
        let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
        XCTAssertEqual(table.numberOfRows, 6)
        XCTAssertEqual(table.tableColumns.count, 9)
        XCTAssertEqual(table.tableColumns[1].title, "label")
        XCTAssertEqual(table.tableColumns[1].headerToolTip, "label (VARCHAR)")
        let null = try XCTUnwrap((viewer.tableView(table, viewFor: table.tableColumns[1], row: 0) as? NSTableCellView)?.textField)
        let blank = try XCTUnwrap((viewer.tableView(table, viewFor: table.tableColumns[1], row: 1) as? NSTableCellView)?.textField)
        let literal = try XCTUnwrap((viewer.tableView(table, viewFor: table.tableColumns[1], row: 3) as? NSTableCellView)?.textField)
        XCTAssertEqual(null.stringValue, "NULL")
        XCTAssertEqual(blank.stringValue, "")
        XCTAssertEqual(literal.stringValue, "NULL")
        XCTAssertNotEqual(null.font, literal.font)
        XCTAssertNotEqual(null.textColor, literal.textColor)
        XCTAssertFalse(table.tableColumns[1].isEditable)
        XCTAssertFalse(viewer.tableView(table, shouldEdit: table.tableColumns[1], row: 0))
        let scroll = try XCTUnwrap(find(NSScrollView.self, in: viewer.view))
        XCTAssertTrue(scroll.hasHorizontalScroller && scroll.hasVerticalScroller)
    }

    func testErrorsRetryReloadAndCloseDiscardObsoleteResults() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".PARQUET")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ParquetSession(url: url)
        await settled(session)
        guard case .failed = session.state else { return XCTFail("Missing file must fail") }
        try Data("corrupt".utf8).write(to: url)
        session.reload(from: url)
        await settled(session)
        guard case .failed = session.state else { return XCTFail("Corrupt file must fail") }
        try Data(contentsOf: fixture).write(to: url)
        session.reload(from: url)
        let reloadedPage = try await loadedPage(session)
        XCTAssertEqual(reloadedPage.totalRows, 6)
        session.reload(from: fixture)
        session.reload(from: url.deletingLastPathComponent().appendingPathComponent("missing.parquet"))
        await settled(session)
        guard case .failed = session.state else { return XCTFail("Old load replaced newer failure") }
        session.reload(from: fixture)
        session.close()
        // Let a cancelled load complete; it must not resurrect a closed tab's result buffers.
        try await Task.sleep(nanoseconds: 100_000_000)
        guard case .closed = session.state else { return XCTFail("Closed session accepted a result") }
    }

    func testDirectDocumentReadAndSaveMenuGuards() async throws {
        let store = OpenDocumentsStore.shared
        let previouslyActive = store.activeDocument
        let document = Document()
        defer {
            document.close()
            if let previouslyActive { store.select(previouslyActive) }
        }
        try document.read(from: fixture, ofType: ParquetPage.typeIdentifier)
        XCTAssertTrue(document.isReadOnly)
        XCTAssertTrue(Document.readableTypes.contains(ParquetPage.typeIdentifier))
        XCTAssertFalse(Document.writableTypes.contains(ParquetPage.typeIdentifier))
        XCTAssertEqual(try DocumentController().typeForContents(of: fixture), ParquetPage.typeIdentifier)
        store.register(document)
        store.select(document)
        let dispatcher = AppCommandDispatcher()
        for action in [#selector(AppCommandDispatcher.saveCurrentDocument(_:)),
                       #selector(AppCommandDispatcher.saveCurrentDocumentAs(_:)),
                       #selector(AppCommandDispatcher.formatJSON(_:)),
                       #selector(AppCommandDispatcher.showGoToLine(_:)),
                       #selector(AppCommandDispatcher.performEditorSearchAction(_:))] {
            XCTAssertFalse(dispatcher.validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: "")))
        }
        XCTAssertTrue(dispatcher.validateMenuItem(NSMenuItem(title: "", action: #selector(AppCommandDispatcher.closeCurrentDocument(_:)), keyEquivalent: "")))
    }

    private func checkWorkspace(parquetURLs: [URL]) async throws {
        _ = NSApplication.shared
        let bytes = try parquetURLs.map { try Data(contentsOf: $0) }
        let textURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "one\ntwo".write(to: textURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textURL) }
        let store = OpenDocumentsStore()
        let controller = DocumentController()
        let opener = WorkspaceDocumentOpener(documentController: controller, openDocumentsStore: store)
        let router = WorkspaceDocumentCoordinator(documentOpener: opener, openDocumentsStore: store,
                                                  closedDocumentHistory: ClosedDocumentHistory(), documentController: controller)
        let workspace = EditorContentViewController(documentStore: store, documentRouter: router)
        _ = workspace.view
        defer { store.documents.forEach { $0.close() } }
        let urls = [textURL] + parquetURLs
        let failures = await opener.openInBackground(urls, activate: textURL, fallbackDocument: nil,
                                                     presentDocument: { store.select($0) }, noDocumentFallback: { XCTFail("No document") })
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(store.documents.count, urls.count)
        let text = try XCTUnwrap(store.activeDocument)
        let editor = text.editorViewController(onFileSystemURLsDropped: { _ in })
        XCTAssertTrue(workspace.goToLine(2))
        for url in parquetURLs {
            let document = try XCTUnwrap(controller.document(for: url) as? Document)
            let session = try XCTUnwrap(document.parquetSession)
            let page = try await loadedPage(session)
            XCTAssertEqual(page.rows.count, Int(min(Int64(1_000), page.totalRows)))
            store.select(document)
            XCTAssertFalse(workspace.goToLine(2))
            XCTAssertFalse(workspace.performSearchAction(.replace))
            workspace.duplicateSelectedLines()
            workspace.deleteCurrentLine()
            workspace.formatJSON()
            XCTAssertEqual(editor.text, "one\ntwo")
            let viewer = try XCTUnwrap(document.parquetViewController())
            let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
            table.tableColumns[0].width = 247
            store.select(text)
            XCTAssertTrue(workspace.goToLine(1))
            store.select(document)
            XCTAssertTrue(document.parquetViewController() === viewer)
            XCTAssertEqual(table.tableColumns[0].width, 247)
            XCTAssertTrue(workspace.canGoBack)
            workspace.navigateBack()
            XCTAssertTrue(store.activeDocument === text)
            workspace.navigateForward()
            XCTAssertTrue(store.activeDocument === document)
            document.save(nil)
            document.saveAs(nil)
            document.updateChangeCount(.changeDone)
            XCTAssertFalse(document.isDocumentEdited)
            XCTAssertThrowsError(try document.write(to: url, ofType: "public.plain-text"))
            XCTAssertThrowsError(try document.write(to: textURL, ofType: "public.plain-text"))
            XCTAssertThrowsError(try document.writeSafely(to: textURL, ofType: "public.plain-text", for: .saveAsOperation))
            XCTAssertEqual(try String(contentsOf: textURL, encoding: .utf8), "one\ntwo")
            for operation in [NSDocument.SaveOperationType.saveOperation, .saveAsOperation, .saveToOperation, .autosaveInPlaceOperation] {
                XCTAssertThrowsError(try document.writeSafely(to: url, ofType: ParquetPage.typeIdentifier, for: operation))
            }
            let duplicateFailures = await opener.openInBackground([url], activate: url, fallbackDocument: nil,
                                                                  presentDocument: { store.select($0) }, noDocumentFallback: {})
            XCTAssertTrue(duplicateFailures.isEmpty)
            XCTAssertTrue(controller.document(for: url) === document)
            XCTAssertEqual(store.documents.count, urls.count)
        }
        let references = urls.map { RestorableDocumentReference.file(path: $0.path) }
        store.documents.forEach { $0.close() }
        XCTAssertTrue(store.documents.isEmpty)
        let restored = await opener.restoreSession(references, activate: parquetURLs.last?.path,
                                                  presentDocument: { store.select($0) }, noDocumentFallback: {})
        XCTAssertTrue(restored.didRestore)
        XCTAssertTrue(restored.failures.isEmpty)
        XCTAssertEqual(store.documents.count, urls.count)
        for document in store.documents {
            if let session = document.parquetSession { _ = try await loadedPage(session) }
        }
        store.documents.forEach { $0.close() }
        for (url, original) in zip(parquetURLs, bytes) { XCTAssertEqual(try Data(contentsOf: url), original) }
    }

    private func settled(_ session: ParquetSession) async {
        let done = expectation(description: "Parquet load completed")
        let token = session.observe {
            if case .loading = session.state { return }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 20)
        token.cancel()
    }

    private func loadedPage(_ session: ParquetSession) async throws -> ParquetPage {
        await settled(session)
        guard case .loaded(let page) = session.state else {
            throw ParquetQueryError(message: session.statusText)
        }
        return page
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        (view as? T) ?? view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }
}
