import AppKit
import DuckDB
import XCTest
@testable import vmini

@MainActor
final class ParquetQueryTests: XCTestCase {
    func testSortAndSearchReachRowsBeyondTheDisplayedBatch() async throws {
        let url = try makeFile("SELECT i AS id, 'Customer ' || (i % 5)::VARCHAR AS label FROM range(1505) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try Data(contentsOf: url)
        let original = try await ParquetPage.load(from: url)
        let id = original.columns[0]
        var query = ParquetQuery()
        query.cycleSort(column: id)
        query.cycleSort(column: id)
        let descending = try await ParquetPage.load(from: url, query: query)
        XCTAssertEqual(descending.rows.first?[0], "1504")
        XCTAssertEqual(descending.rows.last?[0], "505")
        XCTAssertEqual(descending.rows.count, 1000)
        XCTAssertEqual(descending.matchingRows, 1505)
        query.search = "customer"
        let allMatches = try await ParquetPage.load(from: url, query: query)
        XCTAssertEqual(allMatches.matchingRows, 1505)
        XCTAssertEqual(allMatches.rows.count, 1000)
        query.search = "CUSTOMER 4"
        let searched = try await ParquetPage.load(from: url, query: query)
        XCTAssertEqual(searched.matchingRows, 301)
        XCTAssertEqual(searched.rows.first?[0], "1504")
        query.filters[id] = .init(operation: .greaterEqual, value: "1200")
        let combined = try await ParquetPage.load(from: url, query: query)
        XCTAssertEqual(combined.matchingRows, 61)
        XCTAssertEqual(combined.totalRows, 1505)
        query.cycleSort(column: id)
        XCTAssertNil(query.sort)
        let unsorted = try await ParquetPage.load(from: url, query: query)
        XCTAssertEqual(unsorted.rows.first?[0], "1204")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testRareFilterMatchesInSmallRowGroupsStayWithinMemoryLimit() async throws {
        // Sparse matches across many row groups made DuckDB buffer every batch to keep file order under LIMIT.
        let columns = (1..<8).map { "'value ' || ((i // 7) * \($0))::VARCHAR AS c\($0)" }.joined(separator: ", ")
        let url = try makeFile("SELECT i AS id, 'store ' || (i % 2003)::VARCHAR AS store, \(columns) FROM range(200000) t(i)",
                               options: ", ROW_GROUP_SIZE 2048")
        defer { try? FileManager.default.removeItem(at: url) }
        let page = try await ParquetPage.load(from: url)
        var query = ParquetQuery()
        query.filters = [page.columns[1]: .init(operation: .contains, value: "store 2002")]
        let connection = try ParquetConnection(memoryLimit: "16MB")
        _ = try connection.query("SET threads = 4")
        let sql = try query.sql(columns: page.columns, connection: connection)
        let rows = try connection.query(sql.rows, bindings: [.text(url.path)] + sql.bindings)
        XCTAssertEqual(rows.count, 99)
        XCTAssertEqual(rows.prefix(2).map { $0[0] }, ["2002", "4005"], "Filtered rows keep file order")
    }

    func testNestedAndBinaryValuesLoadAsText() async throws {
        let url = try makeFile("SELECT 1 AS id, [1, 2] AS list_col, {'a': 1} AS struct_col, MAP {'k': 1} AS map_col, 'ab'::BLOB AS blob_col")
        defer { try? FileManager.default.removeItem(at: url) }
        var query = ParquetQuery()
        let page = try await ParquetPage.load(from: url)
        XCTAssertEqual(page.rows.first?.compactMap { $0 }.count, 5)
        query.filters = [page.columns[1]: .init(operation: .isNotNull)]
        query.sort = .init(column: page.columns[0])
        let filtered = try await ParquetPage.load(from: url, query: query)
        XCTAssertEqual(filtered.rows.first?[1], "[1, 2]")
    }

    func testFilesWithAFileRowNumberColumnStillSortAndFilter() async throws {
        let url = try makeFile("SELECT i AS file_row_number, 9 - i AS score FROM range(10) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let page = try await ParquetPage.load(from: url)
        var query = ParquetQuery()
        query.sort = .init(column: page.columns[1])
        query.filters = [page.columns[0]: .init(operation: .greaterEqual, value: "5")]
        let sorted = try await ParquetPage.load(from: url, query: query)
        XCTAssertEqual(sorted.rows.map { $0[0] }, ["9", "8", "7", "6", "5"])
        XCTAssertEqual(sorted.matchingRows, 5)
    }

    func testTypedFiltersNullsAndStableSortTies() async throws {
        let url = try makeFile("""
            SELECT * FROM (VALUES
                (1, 10, DATE '2025-01-14', TIMESTAMP '2025-01-14 10:00:00', TIME '10:00:00', true, 90071992547409.1234::DECIMAL(20,4)),
                (2, 2, DATE '2025-01-14', TIMESTAMP '2025-01-14 12:00:00', TIME '12:00:00', false, 90071992547409.1235::DECIMAL(20,4)),
                (3, NULL, DATE '2025-01-15', NULL, NULL, NULL, NULL),
                (4, 2, NULL, TIMESTAMP '2025-01-16 00:00:00', TIME '09:00:00', false, 1.0000::DECIMAL(20,4))
            ) t(id, score, day, stamp, time, flag, amount)
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        let page = try await ParquetPage.load(from: url)
        var query = ParquetQuery()
        query.sort = .init(column: page.columns[1])
        let ascendingIDs = try await ids(url, query)
        XCTAssertEqual(ascendingIDs, ["2", "4", "1", "3"])
        query.sort?.ascending = false
        let descendingIDs = try await ids(url, query)
        XCTAssertEqual(descendingIDs, ["1", "2", "4", "3"])
        query.sort = nil
        let cases: [(Int, ParquetQuery.Operator, String, [String])] = [
            (1, .equals, "2", ["2", "4"]), (1, .notEquals, "2", ["1"]), (1, .greater, "2", ["1"]),
            (1, .less, "10", ["2", "4"]), (1, .greaterEqual, "10", ["1"]),
            (1, .lessEqual, "2", ["2", "4"]), (1, .isNull, "", ["3"]),
            (1, .isNotNull, "", ["1", "2", "4"]), (2, .equals, "2025-01-14", ["1", "2"]),
            (2, .greater, "2025-01-14", ["3"]), (2, .less, "2025-01-15", ["1", "2"]),
            (3, .equals, "2025-01-14", ["1", "2"]), (3, .greater, "2025-01-14", ["4"]),
            (4, .less, "10:00:00", ["4"]), (5, .isTrue, "", ["1"]),
            (5, .isFalse, "", ["2", "4"]), (5, .isNull, "", ["3"]),
            (6, .equals, "90071992547409.1234", ["1"]),
            (6, .greater, "90071992547409.1234", ["2"]),
        ]
        for (index, operation, value, expected) in cases {
            query.filters = [page.columns[index]: .init(operation: operation, value: value)]
            let filteredIDs = try await ids(url, query)
            XCTAssertEqual(filteredIDs, expected, "\(index) \(operation) \(value)")
        }
        query.filters = [page.columns[1]: .init(operation: .equals, value: "2"),
                         page.columns[5]: .init(operation: .isFalse)]
        let combinedIDs = try await ids(url, query)
        XCTAssertEqual(combinedIDs, ["2", "4"])
        for (index, value) in [(1, "1.5"), (1, "1 OR true"), (2, "2025-02-30"), (6, "90071992547409.12345")] {
            query.filters = [page.columns[index]: .init(operation: .equals, value: value)]
            do {
                _ = try await ParquetPage.load(from: url, query: query)
                XCTFail("Invalid input must be rejected: \(value)")
            } catch { XCTAssertTrue(error is ParquetQueryError) }
        }
    }

    func testLiteralTextUnusualIdentifiersAndEmptyStrings() async throws {
        let url = try makeFile(#"SELECT * FROM (VALUES (1, 'O''Brien %_\ 雪'), (2, 'plain'), (3, ''), (4, NULL)) t("select", "na""me 雪")"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let page = try await ParquetPage.load(from: url)
        let name = page.columns[1]
        var query = ParquetQuery()
        query.sort = .init(column: page.columns[0], ascending: false)
        for operation in [ParquetQuery.Operator.contains, .startsWith] {
            query.filters = [name: .init(operation: operation, value: #"o'brien %_\ 雪"#)]
            let literalIDs = try await ids(url, query)
            XCTAssertEqual(literalIDs, ["1"])
        }
        query.filters = [name: .init(operation: .equals, value: #"o'brien %_\ 雪"#)]
        let caseMismatchIDs = try await ids(url, query)
        XCTAssertEqual(caseMismatchIDs, [], "Equals is case-sensitive")
        query.filters = [name: .init(operation: .equals, value: #"O'Brien %_\ 雪"#)]
        let exactIDs = try await ids(url, query)
        XCTAssertEqual(exactIDs, ["1"])
        query.filters = [name: .init(operation: .equals, value: "")]
        let emptyStringIDs = try await ids(url, query)
        XCTAssertEqual(emptyStringIDs, ["3"])
        query.filters = [name: .init(operation: .isNull)]
        let nullIDs = try await ids(url, query)
        XCTAssertEqual(nullIDs, ["4"])
        query.filters = [name: .init(operation: .contains, value: "' OR true --")]
        let injectionIDs = try await ids(url, query)
        XCTAssertEqual(injectionIDs, [])
        query.filters = [:]
        query.search = #"%_\"#
        let searchIDs = try await ids(url, query)
        XCTAssertEqual(searchIDs, ["1"])
        query.search = ""
        query.sort = .init(column: .init(name: "select\"; DROP TABLE data; --", type: "INTEGER"))
        do { _ = try await ParquetPage.load(from: url, query: query); XCTFail("Unknown columns must be rejected") }
        catch { XCTAssertTrue(error is ParquetQueryError) }
    }

    func testSessionCancelsObsoleteQueriesPreservesValidRowsAndClearsFilters() async throws {
        let url = try makeFile("SELECT i AS id, (i % 2)::BOOLEAN AS flag FROM range(1505) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ParquetSession(url: url)
        defer { session.close() }
        let page = try await loaded(session)
        var query = ParquetQuery()
        query.sort = .init(column: page.columns[0], ascending: false)
        query.filters[page.columns[0]] = .init(operation: .greaterEqual, value: "1000")
        session.apply(query, debounce: true)
        XCTAssertEqual(session.statusText, "\(1505.localizedCount) rows", "Status keeps the shown rows' count while loading")
        query.filters[page.columns[0]]?.value = "1504"
        session.apply(query)
        let result = try await loaded(session)
        XCTAssertEqual(result.rows.first?[0], "1504")
        XCTAssertEqual(session.statusText, "1 of \(1505.localizedCount) rows")
        query.filters[page.columns[0]]?.value = "invalid"
        session.apply(query)
        await settled(session)
        guard case .failed = session.state else { return XCTFail("Invalid input must fail") }
        XCTAssertEqual(session.page?.rows, result.rows)
        XCTAssertEqual(session.statusText, "1 of \(1505.localizedCount) rows")
        session.clearFilters()
        let cleared = try await loaded(session)
        XCTAssertEqual(cleared.rows.first?[0], "1504")
        XCTAssertFalse(cleared.query.isFiltered)
        XCTAssertEqual(session.statusText, "\(1505.localizedCount) rows")
        query = session.query
        query.search = "missing"
        session.apply(query)
        let missingCount = try await loaded(session).matchingRows
        XCTAssertEqual(missingCount, 0)
        session.apply(ParquetQuery(), debounce: true)
        session.close()
        try await Task.sleep(nanoseconds: 350_000_000)
        guard case .closed = session.state else { return XCTFail("Closed session accepted a result") }
        XCTAssertNil(session.page)
    }

    func testFilteredRowsAppearBeforeTheirCountAndCountFailuresAreReported() async throws {
        let url = try makeFile("SELECT i AS id FROM range(1505) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ParquetSession(url: url)
        defer { session.close() }
        let page = try await loaded(session)
        var statuses: [String] = []
        var rowsWhileCounting: Int?
        let token = session.observe {
            statuses.append(session.statusText)
            if session.isCounting { rowsWhileCounting = session.page?.rows.count }
        }
        var query = ParquetQuery()
        query.filters[page.columns[0]] = .init(operation: .greaterEqual, value: "1500")
        session.apply(query)
        let counted = try await loaded(session)
        XCTAssertEqual(rowsWhileCounting, 5, "Rows must be shown while counting")
        XCTAssertTrue(statuses.contains("Counting matches… · \(1505.localizedCount) rows"))
        XCTAssertEqual(counted.matchingRows, 5)
        XCTAssertEqual(session.statusText, "5 of \(1505.localizedCount) rows")
        token.cancel()
        // Removing the file once rows are shown makes only the follow-up count fail.
        let failing = session.observe { if session.isCounting { try? FileManager.default.removeItem(at: url) } }
        query.filters[page.columns[0]]?.value = "1504"
        session.apply(query)
        let uncounted = try await loaded(session)
        failing.cancel()
        XCTAssertEqual(uncounted.rows.map { $0[0] }, ["1504"])
        XCTAssertNil(uncounted.matchingRows, "A failed count must not look like zero matches")
        XCTAssertNotNil(session.countError)
        XCTAssertEqual(session.statusText, "Could not count matches · \(1505.localizedCount) rows")
    }

    func testReloadRetainsCompatibleFiltersAndReportsRemovedColumns() async throws {
        let original = try makeFile("SELECT i AS id, 'label' AS label FROM range(5) t(i)")
        let replacement = try makeFile("SELECT i AS id, true AS renamed FROM range(5) t(i)")
        defer {
            try? FileManager.default.removeItem(at: original)
            try? FileManager.default.removeItem(at: replacement)
        }
        let session = ParquetSession(url: original)
        defer { session.close() }
        let page = try await loaded(session)
        var query = ParquetQuery()
        query.filters[page.columns[0]] = .init(operation: .greaterEqual, value: "3")
        query.filters[page.columns[1]] = .init(operation: .contains, value: "label")
        query.sort = .init(column: page.columns[1])
        session.apply(query)
        _ = try await loaded(session)
        session.reload(from: replacement)
        let reloaded = try await loaded(session)
        XCTAssertTrue(reloaded.didResetQuery)
        XCTAssertNil(session.query.sort)
        XCTAssertEqual(session.query.filters.count, 1)
        XCTAssertEqual(reloaded.matchingRows, 2)
        XCTAssertEqual(reloaded.rows.compactMap { $0[0] }, ["3", "4"])
    }

    func testDataCellsFollowTheEditorFontFamily() async throws {
        let originalDefaults = EditorSettings.userDefaults
        let suiteName = "vmini.tests.parquet-font.\(UUID())"
        EditorSettings.userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            EditorSettings.userDefaults.removePersistentDomain(forName: suiteName)
            EditorSettings.userDefaults = originalDefaults
        }
        EditorSettings.setFontID(.menlo)
        let url = try makeFile("SELECT i AS id, 'v' || i::VARCHAR AS label FROM range(5) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ParquetSession(url: url)
        defer { session.close() }
        _ = try await loaded(session)
        let viewer = ParquetViewController(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: .titled, backing: .buffered, defer: false)
        window.contentViewController = viewer
        viewer.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
        func font(column: Int) -> NSFont? {
            (table.view(atColumn: column, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField?.font
        }
        XCTAssertEqual(font(column: 2)?.familyName, "Menlo")
        XCTAssertEqual(font(column: 2)?.pointSize, ParquetTableStyle.Layout.cellFontSize, "Cells keep their own size")
        XCTAssertNotEqual(font(column: 0)?.familyName, "Menlo", "Row numbers stay in the system font")
        EditorSettings.setFontID(.systemMonospaced)
        XCTAssertNotEqual(font(column: 2)?.familyName, "Menlo", "Changing the editor font refreshes cells")
    }

    func testWideTablesOnlyCreateCellsForNearbyColumns() throws {
        let columns = (0..<120).map { "i * \($0) AS c\($0)" }.joined(separator: ", ")
        let url = try makeFile("SELECT \(columns) FROM range(40) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ParquetSession(url: url)
        defer { session.close() }
        while case .loading = session.state { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
        let viewer = ParquetViewController(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: .titled, backing: .buffered, defer: false)
        window.contentViewController = viewer
        window.setContentSize(NSSize(width: 800, height: 500))
        viewer.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
        let last = table.numberOfColumns - 1
        XCTAssertNotNil(table.view(atColumn: 1, row: 0, makeIfNecessary: true))
        XCTAssertNil(table.view(atColumn: last, row: 0, makeIfNecessary: true), "Far-off columns get no cell views")
        let scroll = try XCTUnwrap(table.enclosingScrollView)
        scroll.contentView.scroll(to: NSPoint(x: table.frame.width, y: scroll.contentView.bounds.minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        viewer.view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(table.view(atColumn: last, row: 0, makeIfNecessary: true), "Scrolling realizes newly visible columns")
        XCTAssertNil(table.view(atColumn: 1, row: 0, makeIfNecessary: false), "Columns left behind release their views")
    }

    func testTableStaysHiddenUntilTheFirstPageLoads() async throws {
        let url = try makeFile("SELECT i AS id FROM range(10) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ParquetSession(url: url)
        defer { session.close() }
        let viewer = ParquetViewController(session: session)
        viewer.view.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(find(NSTableView.self, in: viewer.view)?.enclosingScrollView)
        XCTAssertTrue(scrollView.isHidden, "An empty header must not show while the file opens")
        _ = try await loaded(session)
        XCTAssertFalse(scrollView.isHidden)
    }

    func testSkeletonBarsFollowColumnsScrolledWhileHidden() async throws {
        let columns = (0..<12).map { "'v' || i::VARCHAR AS c\($0)" }.joined(separator: ", ")
        let url = try makeFile("SELECT i AS id, \(columns) FROM range(40) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ParquetSession(url: url)
        defer { session.close() }
        _ = try await loaded(session)
        let viewer = ParquetViewController(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: .titled, backing: .buffered, defer: false)
        window.contentViewController = viewer
        viewer.view.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        viewer.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
        let skeleton = try XCTUnwrap(find(ParquetSkeletonView.self, in: viewer.view))
        // Scroll while the skeleton is hidden, as when a new row count toggles the vertical scroller.
        table.scroll(NSPoint(x: 437, y: 0))
        viewer.tableView(table, didClick: table.tableColumns[1])
        XCTAssertFalse(skeleton.isHidden)
        let path = try XCTUnwrap((skeleton.subviews.first?.layer?.sublayers?.first as? CAShapeLayer)?.path)
        let rowMid = table.rowHeight * 1.5
        var checked = 0
        for index in table.tableColumns.indices {
            let cell = skeleton.convert(table.rect(ofColumn: index), from: table)
            guard cell.minX >= 0, cell.maxX <= skeleton.bounds.width else { continue }
            XCTAssertTrue(path.contains(CGPoint(x: cell.minX + 14, y: rowMid)), "Bar must start inside column \(index)")
            XCTAssertFalse(path.contains(CGPoint(x: cell.minX + 4, y: rowMid)), "Bar must not cross column \(index)'s left edge")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
        _ = try await loaded(session)
    }

    func testNativeControlsSubmitFiltersAndKeepColumnWidths() async throws {
        let url = try makeFile("SELECT i AS id, 'Customer ' || i::VARCHAR AS label FROM range(30) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ParquetSession(url: url)
        defer { session.close() }
        _ = try await loaded(session)
        let viewer = ParquetViewController(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.contentViewController = viewer
        viewer.view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        viewer.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(find(NSTableView.self, in: viewer.view))
        let header = try XCTUnwrap(table.headerView as? ParquetTableHeaderView)
        let column = table.tableColumns[1]
        column.width = 247
        let skeleton = try XCTUnwrap(find(ParquetSkeletonView.self, in: viewer.view))
        XCTAssertTrue(skeleton.isHidden)
        viewer.tableView(table, didClick: column)
        XCTAssertEqual(session.statusText, "\(session.page?.totalRows.localizedCount ?? "") rows")
        XCTAssertFalse(skeleton.isHidden, "Sorting must show the skeleton over the table body")
        XCTAssertNil(skeleton.layer?.animation(forKey: "pulse"), "Only the bars may pulse, or stale rows show through")
        XCTAssertNotNil(skeleton.subviews.first?.layer?.animation(forKey: "pulse"))
        XCTAssertEqual(skeleton.frame.maxY, viewer.view.convert(header.bounds, from: header).minY, accuracy: 0.5,
                       "Skeleton must stop at the header so filters stay visible")
        _ = try await loaded(session)
        XCTAssertTrue(skeleton.isHidden)
        XCTAssertEqual(column.width, 247)
        XCTAssertTrue(table.tableColumns[1] === column)
        XCTAssertEqual((column.headerCell as? ParquetTableHeaderCell)?.sortAscending, true)
        let filter = try XCTUnwrap(header.subviews.compactMap { $0 as? ParquetColumnFilterView }.first)
        let input = try XCTUnwrap(filter.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertTrue(header.accessibilityChildren()?.contains { ($0 as? NSTextField) === input } == true)
        let searchField = try XCTUnwrap(find(NSSearchField.self, in: viewer.view))
        let tabOrder = sequence(first: searchField as NSView) { $0.nextKeyView }.prefix(20).map { $0 }
        XCTAssertTrue(tabOrder.dropFirst().contains { $0 === searchField }, "Tab must loop back to search")
        XCTAssertLessThan(try XCTUnwrap(tabOrder.firstIndex { $0 === input }), try XCTUnwrap(tabOrder.firstIndex { $0 === table }),
                          "Tab must reach column filters, then the table")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("vmini.tests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        viewer.pasteboard = pasteboard
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        XCTAssertFalse(viewer.validateMenuItem(copyItem), "Copy needs a selected cell")
        let parquetTable = try XCTUnwrap(table as? ParquetTableView)
        parquetTable.cellSelection = .init(anchor: .init(row: 2, column: 1), focus: .init(row: 0, column: 0))
        XCTAssertTrue(viewer.validateMenuItem(copyItem))
        viewer.copy(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "1\t0\n2\t1\n3\t2", "Copy takes the selected rectangle")
        table.deselectAll(nil)
        input.stringValue = "29"
        filter.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: input))
        let filteredCount = try await loaded(session).matchingRows
        XCTAssertEqual(filteredCount, 1)
        XCTAssertEqual(table.numberOfRows, 1)
        viewer.view.layoutSubtreeIfNeeded()
        let visible = try XCTUnwrap(table.enclosingScrollView).documentVisibleRect
        XCTAssertEqual(visible.intersection(table.rect(ofRow: 0)).height, table.rowHeight,
                       "First row must be visible after filtering: \(visible)")
        XCTAssertTrue(header.subviews.contains { $0 === filter })
        let search = try XCTUnwrap(find(NSSearchField.self, in: viewer.view))
        search.stringValue = "no match"
        viewer.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        let searchCount = try await loaded(session).matchingRows
        XCTAssertEqual(searchCount, 0)
        XCTAssertEqual(table.numberOfRows, 0)
        XCTAssertEqual(table.gridStyleMask, [])
        XCTAssertTrue(viewer.view.subviews.contains { self.find(NSTextField.self, in: $0)?.stringValue == "No rows" && !$0.isHidden })
        let clear = try XCTUnwrap(viewer.view.subviews.lazy.compactMap { self.find(NSButton.self, titled: "Clear all", in: $0) }.first)
        XCTAssertTrue(clear.isEnabled)
        clear.performClick(nil)
        _ = try await loaded(session)
        XCTAssertEqual(table.numberOfRows, 30)
        XCTAssertFalse(table.gridStyleMask.isEmpty)
        XCTAssertEqual(search.stringValue, "")
        XCTAssertEqual(input.stringValue, "")
        XCTAssertEqual(column.width, 247)
        XCTAssertEqual(session.query.sort?.ascending, true)
    }

    func testFloatFiltersCompareInColumnPrecision() async throws {
        let url = try makeFile("SELECT * FROM (VALUES (1, 0.1::FLOAT), (2, 0.2::FLOAT)) t(id, f)")
        defer { try? FileManager.default.removeItem(at: url) }
        let column = try await ParquetPage.load(from: url).columns[1]
        var query = ParquetQuery()
        for (operation, expected) in [(ParquetQuery.Operator.equals, ["1"]), (.greater, ["2"]), (.lessEqual, ["1"])] {
            query.filters = [column: .init(operation: operation, value: "0.1")]
            let filteredIDs = try await ids(url, query)
            XCTAssertEqual(filteredIDs, expected, "\(operation)")
        }
    }

    func testFileWiderThanRowLimitOpens() async throws {
        let columns = (0...ParquetPage.rowLimit).map { "i AS c\($0)" }.joined(separator: ", ")
        let url = try makeFile("SELECT \(columns) FROM range(3) t(i)")
        defer { try? FileManager.default.removeItem(at: url) }
        let page = try await ParquetPage.load(from: url)
        XCTAssertEqual(page.columns.count, ParquetPage.rowLimit + 1)
        XCTAssertEqual(page.rows.count, 3)
    }

    private func makeFile(_ select: String, options: String = "") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quotes ' %_ 雪 \(UUID()).parquet")
        let database = try Database(store: .inMemory)
        let connection = try database.connect()
        try connection.execute("COPY (\(select)) TO '\(url.path.replacingOccurrences(of: "'", with: "''"))' (FORMAT PARQUET\(options))")
        return url
    }

    private func ids(_ url: URL, _ query: ParquetQuery) async throws -> [String] {
        try await ParquetPage.load(from: url, query: query).rows.compactMap { $0[0] }
    }

    private func settled(_ session: ParquetSession) async {
        let done = expectation(description: "Query settled")
        let observation = session.observe {
            if case .loading = session.state { return }
            if session.isCounting { return }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 20)
        observation.cancel()
    }

    private func loaded(_ session: ParquetSession) async throws -> ParquetPage {
        await settled(session)
        guard case .loaded(let page) = session.state else { throw ParquetQueryError(message: session.statusText) }
        return page
    }

    private func find(_ type: NSButton.Type, titled title: String, in view: NSView) -> NSButton? {
        (view as? NSButton).flatMap { $0.title == title ? $0 : nil } ?? view.subviews.lazy.compactMap { self.find(type, titled: title, in: $0) }.first
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        (view as? T) ?? view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }
}
