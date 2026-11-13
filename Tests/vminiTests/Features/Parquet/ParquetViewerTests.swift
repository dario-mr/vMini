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
            XCTAssertEqual(session.statusText, "\(count.localizedCount) rows")
            XCTAssertEqual(page.columns.first?.name, "id")
            let viewer = ParquetViewController(session: session)
            let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
            XCTAssertEqual(table.tableColumns.map(\.title), ["#", "id"])
            XCTAssertEqual(table.numberOfRows, min(count, 1_000))
        }

        let session = ParquetSession(url: fixture)
        defer { session.close() }
        let page = try await loadedPage(session)
        XCTAssertEqual(page.columns[2].type, "DECIMAL(20,4)")
        XCTAssertEqual(page.rows[1][2], "90071992547409.1234")
        let viewer = ParquetViewController(session: session)
        let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
        XCTAssertEqual(table.numberOfRows, 6)
        XCTAssertEqual(table.tableColumns.count, 10)
        XCTAssertEqual(table.tableColumns[2].title, "label")
        XCTAssertEqual((table.tableColumns[2].headerCell as? ParquetTableHeaderCell)?.typeName, "VARCHAR")
        let null = try XCTUnwrap((viewer.tableView(table, viewFor: table.tableColumns[2], row: 0) as? NSTableCellView)?.textField)
        let blank = try XCTUnwrap((viewer.tableView(table, viewFor: table.tableColumns[2], row: 1) as? NSTableCellView)?.textField)
        let literal = try XCTUnwrap((viewer.tableView(table, viewFor: table.tableColumns[2], row: 3) as? NSTableCellView)?.textField)
        XCTAssertEqual(null.stringValue, "NULL")
        XCTAssertEqual(blank.stringValue, "")
        XCTAssertEqual(literal.stringValue, "NULL")
        XCTAssertNotEqual(null.font, literal.font)
        XCTAssertNotEqual(null.textColor, literal.textColor)
        XCTAssertFalse(table.tableColumns[2].isEditable)
        XCTAssertFalse(viewer.tableView(table, shouldEdit: table.tableColumns[2], row: 0))
        let scroll = try XCTUnwrap(find(NSScrollView.self, in: viewer.view))
        XCTAssertTrue(scroll.hasHorizontalScroller && scroll.hasVerticalScroller)
        let rowNumber = try XCTUnwrap((viewer.tableView(table, viewFor: table.tableColumns[0], row: 5) as? NSTableCellView)?.textField)
        XCTAssertEqual(rowNumber.stringValue, "6")
        let decimal = try XCTUnwrap((viewer.tableView(table, viewFor: table.tableColumns[3], row: 1) as? NSTableCellView)?.textField)
        XCTAssertEqual(decimal.stringValue, "90071992547409.1234")
        XCTAssertEqual(decimal.alignment, .right)
        XCTAssertEqual(literal.alignment, .left)
        XCTAssertNil(table.tableColumns[3].sortDescriptorPrototype)
        XCTAssertTrue(try XCTUnwrap(find(NSSearchField.self, in: viewer.view)).isEnabled)
    }

    func testFilterHeaderTracksColumnResizingAndHorizontalScrolling() async throws {
        let session = ParquetSession(url: fixture)
        defer { session.close() }
        _ = try await loadedPage(session)
        let viewer = ParquetViewController(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = viewer
        defer { window.orderOut(nil) }
        viewer.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
        let header = try XCTUnwrap(table.headerView as? ParquetTableHeaderView)
        XCTAssertEqual(header.frame.height, ParquetTableHeaderView.titleHeight + ParquetTableHeaderView.filterHeight)
        XCTAssertFalse(header.subviews.isEmpty)
        XCTAssertLessThan(header.subviews.count, table.tableColumns.count - 1, "Only columns near the visible area get filter controls")
        table.tableColumns[1].width = 247
        viewer.tableViewColumnDidResize(Notification(name: NSTableView.columnDidResizeNotification, object: table))
        table.moveColumn(1, toColumn: 3)
        viewer.tableViewColumnDidMove(Notification(name: NSTableView.columnDidMoveNotification, object: table))
        header.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(table.enclosingScrollView)
        scroll.contentView.scroll(to: NSPoint(x: 200, y: 35))
        scroll.reflectScrolledClipView(scroll.contentView)
        for filter in header.subviews {
            let index = try XCTUnwrap(table.tableColumns.firstIndex { $0.identifier == filter.identifier })
            XCTAssertEqual(filter.frame.minX, header.headerRect(ofColumn: index).minX + 5, accuracy: 0.5)
            XCTAssertEqual(filter.frame.width, header.headerRect(ofColumn: index).width - 10, accuracy: 0.5)
            XCTAssertTrue(filter.subviews.compactMap { $0 as? NSControl }.allSatisfy { $0.isEnabled })
            for case let value as NSTextField in filter.subviews {
                XCTAssertGreaterThan(value.frame.width, 35)
            }
        }
        scroll.contentView.scroll(to: NSPoint(x: table.frame.width, y: scroll.contentView.bounds.minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        header.layoutSubtreeIfNeeded()
        let shown = Set(header.subviews.compactMap { $0.identifier?.rawValue })
        XCTAssertTrue(shown.contains(table.tableColumns.last!.identifier.rawValue), "Scrolling creates controls for newly visible columns")
        XCTAssertFalse(shown.contains(table.tableColumns[1].identifier.rawValue), "Far-off columns drop their controls")
        XCTAssertEqual(table.numberOfRows, 6)
        XCTAssertEqual(session.statusText, "6 rows")
        let previousTheme = ThemeManager.shared.selectedThemeID
        defer { ThemeManager.shared.setThemeID(previousTheme) }
        for theme in [ThemeID.default, .solarizedLight] {
            ThemeManager.shared.setThemeID(theme)
            XCTAssertEqual(table.backgroundColor, AppColors.editorBackground)
            let bitmap = try XCTUnwrap(header.bitmapImageRepForCachingDisplay(in: header.bounds))
            header.cacheDisplay(in: header.bounds, to: bitmap)
            let titleBackground = try XCTUnwrap(bitmap.colorAt(x: 2, y: 5))
            let filterBackground = try XCTUnwrap(bitmap.colorAt(x: 2, y: Int(ParquetTableHeaderView.titleHeight) + 14))
            XCTAssertNotEqual(titleBackground, filterBackground)
            XCTAssertEqual(viewer.view.appearance?.name, theme.preferredAppearance)
        }
    }

    func testFooterRowCountsAndHiddenSyntaxControl() {
        XCTAssertEqual(ParquetSession.rowCountText(totalRows: 30), "30 rows")
        XCTAssertEqual(ParquetSession.rowCountText(totalRows: 30, matchingRows: 1), "1 of 30 rows")
        XCTAssertEqual(ParquetSession.rowCountText(totalRows: 30, matchingRows: 0), "0 of 30 rows")
        XCTAssertEqual(ParquetSession.rowCountText(totalRows: 30, matchingRows: 30), "30 of 30 rows")
        let footer = EditorStatusBarView()
        footer.updateParquet(status: "1,873 of 30,000 rows")
        let label = try? XCTUnwrap(footer.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(label?.stringValue, "1,873 of 30,000 rows")
        let status = label?.attributedStringValue
        let color = { (index: Int) in status?.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor }
        XCTAssertEqual(color(0), AppColors.sidebarText)
        XCTAssertEqual(color(6), AppColors.sidebarText)
        XCTAssertEqual(color(17), AppColors.inactiveTabText, "Only the trailing rows is dimmed")
        XCTAssertEqual((status?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize,
                       EditorStatusBarView.Layout.parquetTextSize)
        XCTAssertTrue(footer.subviews.compactMap { $0 as? NSButton }.allSatisfy(\.isHidden))
    }

    func testScrollingClearsStaleHoverWithoutChangingSelection() throws {
        let row = ParquetTableRowView(frame: NSRect(x: 0, y: 0, width: 100, height: 35))
        let bitmap = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        func background() throws -> NSColor {
            row.cacheDisplay(in: row.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.colorAt(x: 50, y: 17))
        }
        let normal = try background()
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                                                        timestamp: 0, windowNumber: 0, context: nil,
                                                        eventNumber: 0, trackingNumber: 0, userData: nil))
        row.mouseEntered(with: event)
        XCTAssertNotEqual(try background(), normal)
        row.refreshHover()
        XCTAssertEqual(try background(), normal)
        row.needsDisplay = false
        row.refreshHover()
        XCTAssertFalse(row.needsDisplay)
    }

    func testColumnPresentationUsesSchemaWithoutGuessingFromValues() {
        XCTAssertEqual(ParquetColumnKind(type: "DECIMAL(20,4)"), .number)
        XCTAssertEqual(ParquetColumnKind(type: "UBIGINT"), .number)
        XCTAssertEqual(ParquetColumnKind(type: "VARCHAR"), .text)
        XCTAssertEqual(ParquetColumnKind(type: "TIMESTAMP WITH TIME ZONE"), .date)
        XCTAssertEqual(ParquetColumnKind(type: "BOOLEAN"), .boolean)
        for type in ["INTEGER[]", "DECIMAL(20,4)[]", "STRUCT(id INTEGER)", "BLOB"] {
            XCTAssertEqual(ParquetColumnKind(type: type), .other)
        }
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
        workspace.view.frame = NSRect(x: 0, y: 0, width: 1_024, height: 768)
        workspace.view.layoutSubtreeIfNeeded()
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
            var query = ParquetQuery()
            query.search = try XCTUnwrap(page.rows.first?.compactMap { $0 }.first)
            session.apply(query)
            let searched = try await loadedPage(session)
            XCTAssertGreaterThan(try XCTUnwrap(searched.matchingRows), 0)
            XCTAssertEqual(searched.totalRows, page.totalRows)
            let statusBar = try XCTUnwrap(find(EditorStatusBarView.self, in: workspace.view))
            XCTAssertEqual(statusBar.subviews.compactMap { $0 as? NSTextField }.first?.stringValue, session.statusText)
            session.clearFilters()
            _ = try await loadedPage(session)
            table.tableColumns[1].width = 247
            store.select(text)
            XCTAssertTrue(workspace.goToLine(1))
            store.select(document)
            XCTAssertTrue(document.parquetViewController() === viewer)
            XCTAssertEqual(table.tableColumns[1].width, 247)
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
            if session.isCounting { return }
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
