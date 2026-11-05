import Foundation
import UniformTypeIdentifiers

struct ParquetPage: Sendable {
    struct Column: Sendable {
        let name: String
        let type: String
    }

    static let rowLimit = 1_000
    static let typeIdentifier = "com.apache.parquet"
    static let contentType = UTType(importedAs: typeIdentifier, conformingTo: .data)

    let columns: [Column]
    let rows: [[String?]]
    let totalRows: Int64

    static func recognizes(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "parquet"
    }

    // Called only by the session's background task; no engine handles escape this load.
    static func load(from url: URL) async throws -> ParquetPage {
        let connection = try ParquetConnection()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let bindings: [ParquetConnection.Binding] = [.text(url.path)]
            let schema = try connection.query("DESCRIBE SELECT * FROM read_parquet(?)", bindings: bindings)
            try Task.checkCancellation()
            let count = try connection.query("SELECT count(*) FROM read_parquet(?)", bindings: bindings)
            guard let value = count.first?.first, let value, let totalRows = Int64(value) else {
                throw ParquetQueryError(message: "Could not read the Parquet row count.")
            }
            try Task.checkCancellation()
            let rows = try connection.query("SELECT * FROM read_parquet(?) LIMIT \(rowLimit)", bindings: bindings)
            let columns = try schema.map { row -> Column in
                guard row.count >= 2, let name = row[0], let type = row[1] else {
                    throw ParquetQueryError(message: "Could not read the Parquet schema.")
                }
                return Column(name: name, type: type)
            }
            try Task.checkCancellation()
            return ParquetPage(columns: columns, rows: rows, totalRows: totalRows)
        } onCancel: {
            connection.interrupt()
        }
    }
}
