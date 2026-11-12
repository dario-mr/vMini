import Foundation
import XCTest
@testable import vmini

final class ParquetIntegrationTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/scalars.snappy.parquet")
    }

    func testSchemaBoundTypedQueriesAndExactValuesLeaveFixtureUnchanged() throws {
        let bytes = try Data(contentsOf: fixture)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("quotes ' %_ 雪.snappy.parquet")
        try bytes.write(to: file)
        let connection = try ParquetConnection()
        let bindings: [ParquetConnection.Binding] = [.text(file.path)]
        let schema = try connection.query("DESCRIBE SELECT * FROM read_parquet(?)", bindings: bindings)
        XCTAssertEqual(schema.count, 9)
        XCTAssertEqual(schema[2][1], "DECIMAL(20,4)")
        XCTAssertEqual(schema[8][0], "sort \"雪")
        let page = try connection.query("SELECT * FROM read_parquet(?) ORDER BY id LIMIT 1000", bindings: bindings)
        XCTAssertEqual(page.count, 6)
        XCTAssertNil(page[0][1])
        XCTAssertEqual(page[1][1], "")
        XCTAssertEqual(page[2][1], "00123")
        XCTAssertEqual(page[3][1], "NULL")
        XCTAssertEqual(page[1][2], "90071992547409.1234")
        XCTAssertEqual(page[1][8], "9007199254740994")
        XCTAssertEqual(page[1][6], "12:34:56.123456")
        XCTAssertEqual(page[1][7], "2024-02-29 12:34:56.123456")
        let filteredBindings = bindings + [.integer(3)]
        XCTAssertEqual(try connection.query("SELECT count(*) FROM read_parquet(?) WHERE id >= ?", bindings: filteredBindings), [["3"]])
        XCTAssertEqual(try connection.query("""
            SELECT id FROM read_parquet(?) WHERE id >= ?
            ORDER BY "sort ""雪" DESC NULLS LAST, id ASC LIMIT 2
            """, bindings: filteredBindings), [["5"], ["4"]])
        XCTAssertEqual(try connection.query("SELECT id FROM read_parquet(?) WHERE label = ? LIMIT 1000", bindings: bindings + [.text("' OR true --")]), [])
        XCTAssertThrowsError(try connection.query("SELECT * FROM range(1001)"))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try Data(contentsOf: fixture), bytes)
    }

    func testOfflineCodecsAndPublicSwiftAPI() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try ParquetTestFixtures.generate(in: directory)
        let connection = try ParquetConnection()
        XCTAssertEqual(try connection.query("SELECT loaded, install_mode FROM duckdb_extensions() WHERE extension_name = 'parquet'"), [["true", "STATICALLY_LINKED"]])
        for codec in ["snappy", "gzip", "zstd", "uncompressed"] {
            let path = directory.appendingPathComponent("scalars.\(codec).parquet").path
            XCTAssertEqual(try connection.query("SELECT count(*) FROM read_parquet(?)", bindings: [.text(path)]), [["6"]])
        }
    }

    func testMissingAndCorruptFilesThrowInsteadOfReturningEmptyRows() throws {
        let connection = try ParquetConnection()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".parquet")
        XCTAssertThrowsError(try connection.query("SELECT * FROM read_parquet(?) LIMIT 1000", bindings: [.text(file.path)]))
        try Data("not parquet".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try connection.query("SELECT * FROM read_parquet(?) LIMIT 1000", bindings: [.text(file.path)]))
    }

    func testRunningQueryCanBeInterruptedAndConnectionReused() throws {
        let connection = try ParquetConnection()
        let finished = DispatchSemaphore(value: 0)
        let result = ParquetCancellationResult()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { finished.signal() }
            do {
                _ = try connection.query("SELECT sum(sin(i::DOUBLE)) FROM range(1000000000000) t(i)")
            } catch {
                result.set(error)
            }
        }
        // Repeated interrupts also cover cancellation racing with prepare/start.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(10))
        timer.setEventHandler { connection.interrupt() }
        let timerStopped = DispatchSemaphore(value: 0)
        timer.setCancelHandler { timerStopped.signal() }
        timer.resume()
        let completed = finished.wait(timeout: .now() + 5)
        timer.cancel()
        timerStopped.wait()
        guard completed == .success else {
            XCTFail("DuckDB did not cancel within 5 seconds")
            return
        }
        XCTAssertEqual((result.error as? ParquetQueryError)?.interrupted, true,
                       "Expected interruption; got \(result.error?.localizedDescription ?? "successful completion")")
        XCTAssertEqual(try connection.query("SELECT 42"), [["42"]])
    }

    func testMemoryLimitFailsCleanlyAndConnectionCanBeReused() throws {
        let connection = try ParquetConnection(memoryLimit: "32MB")
        do {
            _ = try connection.query("SELECT count(*) FROM (SELECT i FROM range(10000000) t(i) GROUP BY i)")
            XCTFail("Expected a controlled out-of-memory error")
        } catch let error as ParquetQueryError {
            XCTAssertTrue(error.message.contains("Out of Memory"), error.message)
        }
        XCTAssertEqual(try connection.query("SELECT 42"), [["42"]])
    }
}

private final class ParquetCancellationResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?
    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
    func set(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        storedError = error
    }
}
