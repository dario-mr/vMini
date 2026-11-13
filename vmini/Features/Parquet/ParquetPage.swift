import Foundation
import UniformTypeIdentifiers

struct ParquetPage: Sendable {
    struct Column: Hashable, Sendable {
        let name: String
        let type: String
    }

    static let rowLimit = 1_000
    static let typeIdentifier = "com.apache.parquet"
    static let contentType = UTType(importedAs: typeIdentifier, conformingTo: .data)

    struct Schema: Sendable {
        let columns: [Column]
        let totalRows: Int64
    }

    let columns: [Column]
    let rows: [[String?]]
    let totalRows: Int64
    /// Nil while a filtered count is still running.
    var matchingRows: Int64?
    let query: ParquetQuery
    let didResetQuery: Bool

    static func recognizes(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "parquet"
    }

    /// Pass the `schema` of an earlier load of the same file to skip reading it again.
    static func load(from url: URL, query: ParquetQuery = ParquetQuery(), reconcileSchema: Bool = false,
                     countMatches: Bool = true, schema: Schema? = nil) async throws -> ParquetPage {
        var page = try await withConnection { connection in
            let bindings: [ParquetConnection.Binding] = [.text(url.path)]
            let schema = try schema ?? Schema(of: url, connection: connection)
            let columns = schema.columns
            let appliedQuery = reconcileSchema ? query.compatible(with: columns) : query
            let sql = try appliedQuery.sql(columns: columns, connection: connection)
            try Task.checkCancellation()
            let rows = try connection.query(sql.rows, bindings: bindings + sql.bindings)
            return ParquetPage(columns: columns, rows: rows, totalRows: schema.totalRows,
                               matchingRows: appliedQuery.isFiltered ? nil : schema.totalRows,
                               query: appliedQuery, didResetQuery: appliedQuery != query)
        }
        if countMatches, page.matchingRows == nil {
            page.matchingRows = try await Self.countMatches(in: url, query: page.query, columns: page.columns)
        }
        return page
    }

    static func countMatches(in url: URL, query: ParquetQuery, columns: [Column]) async throws -> Int64 {
        try await withConnection { connection in
            let sql = try query.sql(columns: columns, connection: connection)
            try Task.checkCancellation()
            let count = try connection.query("SELECT count(*) FROM read_parquet(?)\(sql.predicate)",
                                             bindings: [.text(url.path)] + sql.bindings)
            guard let value = count.first?.first, let value, let count = Int64(value) else {
                throw ParquetQueryError(message: "Could not count matching rows.")
            }
            return count
        }
    }

    var schema: Schema { Schema(columns: columns, totalRows: totalRows) }

    private static func withConnection<T>(_ body: (ParquetConnection) throws -> T) async throws -> T {
        // Keep user-requested queries running when the window is in the background.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Query Parquet rows")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let connection = try ParquetConnection()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result = try body(connection)
            try Task.checkCancellation()
            return result
        } onCancel: {
            connection.interrupt()
        }
    }
}

private extension ParquetPage.Schema {
    init(of url: URL, connection: ParquetConnection) throws {
        let bindings: [ParquetConnection.Binding] = [.text(url.path)]
        // DESCRIBE returns one row per column, so the result row limit would cap the column count.
        let schema = try connection.query("DESCRIBE SELECT * FROM read_parquet(?)", bindings: bindings, resultRowLimit: nil)
        try Task.checkCancellation()
        let count = try connection.query("SELECT count(*) FROM read_parquet(?)", bindings: bindings)
        guard let value = count.first?.first, let value, let totalRows = Int64(value) else {
            throw ParquetQueryError(message: "Could not read the Parquet row count.")
        }
        columns = try schema.map { row -> ParquetPage.Column in
            guard row.count >= 2, let name = row[0], let type = row[1] else {
                throw ParquetQueryError(message: "Could not read the Parquet schema.")
            }
            return ParquetPage.Column(name: name, type: type)
        }
        self.totalRows = totalRows
    }
}
