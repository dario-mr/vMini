import AppKit
import DuckDB
import XCTest
@testable import vmini

@MainActor
final class ParquetPerformanceTests: XCTestCase {
    private static let sampleCount = 5
    private static let wideViewSampleCount = 20
    // Bump the version when the fixture queries change, so stale cached files are not reused.
    private static let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("vmini-parquet-perf-v1")

    func testLargeFileQueries() async throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh to measure Parquet queries")
        }
        let url = try Self.fixture("tall", """
            SELECT i AS id, random() AS score, 'cat' || (i % 50)::VARCHAR AS category, 'C' || i::VARCHAR AS code,
                   CASE WHEN i % 7 = 0 THEN NULL ELSE md5(i::VARCHAR) END AS note
            FROM range(10000000) t(i)
            """)
        let columns = try await ParquetPage.load(from: url).columns
        let column = { (name: String) in columns.first { $0.name == name }! }
        var numericSort = ParquetQuery()
        numericSort.sort = .init(column: column("score"), ascending: false)
        var textSort = ParquetQuery()
        textSort.sort = .init(column: column("code"), ascending: false)
        var rareFilter = ParquetQuery()
        rareFilter.filters = [column("code"): .init(operation: .contains, value: "C99999")]
        var search = ParquetQuery()
        search.search = "zzzz"
        let scenarios: [(String, String, ParquetQuery)] = [
            ("parquet.open", "parquet-query", ParquetQuery()),
            ("parquet.sort.numeric", "parquet-query", numericSort),
            ("parquet.sort.text", "parquet-query", textSort),
            ("parquet.filter.rare", "parquet-query", rareFilter),
            ("parquet.search.no-match", "parquet-search", search),
        ]
        for (id, classification, query) in scenarios {
            do {
                var samples: [Double] = []
                for _ in 0..<Self.sampleCount {
                    let start = DispatchTime.now()
                    _ = try await ParquetPage.load(from: url, query: query)
                    samples.append(Self.milliseconds(since: start))
                }
                PerformanceBenchmark.emit(id, classification: classification,
                                          boundary: "ParquetPage.load rows and matching count, 10M rows",
                                          inputUTF16Length: 0, samples: samples)
            } catch {
                PerformanceBenchmark.emitFailure(id, classification: classification, error)
                XCTFail("\(id): \(error.localizedDescription)")
            }
        }
    }

    func testWideFileView() async throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh to measure the Parquet view")
        }
        let id = "parquet.wide.view"
        let columns = (0..<400).map { $0.isMultiple(of: 2) ? "i * \($0) AS n\($0)" : "'v' || (i % 997)::VARCHAR AS s\($0)" }
        let url = try Self.fixture("wide", "SELECT \(columns.joined(separator: ", ")) FROM range(50000) t(i)")
        let session = ParquetSession(url: url)
        defer { session.close() }
        while case .loading = session.state { try await Task.sleep(nanoseconds: 10_000_000) }
        var samples: [Double] = []
        var largestGrowth = 0
        for _ in 0..<Self.wideViewSampleCount {
            let before = Self.footprintMegabytes()
            let start = DispatchTime.now()
            let viewer = ParquetViewController(session: session)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: .titled,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = viewer
            window.setContentSize(NSSize(width: 1200, height: 800))
            viewer.view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            samples.append(Self.milliseconds(since: start))
            largestGrowth = max(largestGrowth, Self.footprintMegabytes() - before)
            window.contentViewController = nil
            window.close()
        }
        // Realizing every column's cells and filters once cost ~600 MB; nearby columns only should stay small.
        guard largestGrowth < 100 else {
            struct Growth: LocalizedError { let megabytes: Int; var errorDescription: String? { "view grew \(megabytes) MB" } }
            PerformanceBenchmark.emitFailure(id, classification: "parquet-view", Growth(megabytes: largestGrowth))
            return XCTFail("\(id): building a 400-column view grew memory by \(largestGrowth) MB")
        }
        PerformanceBenchmark.emit(id, classification: "parquet-view",
                                  boundary: "ParquetViewController build, layout and first display, 400 columns",
                                  inputUTF16Length: 0, samples: samples)
    }

    private static func fixture(_ name: String, _ select: String) throws -> URL {
        let url = fixtureDirectory.appendingPathComponent("\(name).parquet")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let partial = url.appendingPathExtension("partial")
        try Database(store: .inMemory).connect()
            .execute("COPY (\(select)) TO '\(partial.path)' (FORMAT PARQUET, COMPRESSION ZSTD)")
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }

    private static func milliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private static func footprintMegabytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return Int(info.phys_footprint) / 1_048_576
    }
}
