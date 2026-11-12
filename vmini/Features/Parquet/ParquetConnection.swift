import Cduckdb
import Foundation

struct ParquetQueryError: LocalizedError {
    let message: String
    var interrupted = false
    var errorDescription: String? { message }
}

// The official Swift wrapper has no interrupt API; own C handles rather than inspect private Swift storage.
final class ParquetConnection: @unchecked Sendable {
    enum Binding {
        case text(String)
        case integer(Int64)
    }

    private let database: duckdb_database
    private let connection: duckdb_connection
    private let queryLock = NSLock()

    init(memoryLimit: String = "1GB") throws {
        var config: duckdb_config?
        guard duckdb_create_config(&config) == DuckDBSuccess else {
            throw ParquetQueryError(message: "Could not create DuckDB configuration")
        }
        defer { duckdb_destroy_config(&config) }
        for (key, value) in [
            "memory_limit": memoryLimit, "threads": String(max(2, ProcessInfo.processInfo.activeProcessorCount / 2)), "temp_directory": "",
            "autoinstall_known_extensions": "false", "autoload_known_extensions": "false"
        ] {
            guard duckdb_set_config(config, key, value) == DuckDBSuccess else {
                throw ParquetQueryError(message: "Could not set DuckDB option \(key)")
            }
        }
        var database: duckdb_database?
        var error: UnsafeMutablePointer<CChar>?
        let status = duckdb_open_ext(nil, &database, config, &error)
        defer { if let error { duckdb_free(error) } }
        guard status == DuckDBSuccess, let database else {
            duckdb_close(&database)
            throw ParquetQueryError(message: error.map { String(cString: $0) } ?? "Could not open DuckDB")
        }
        var connection: duckdb_connection?
        guard duckdb_connect(database, &connection) == DuckDBSuccess, let connection else {
            var database: duckdb_database? = database
            duckdb_close(&database)
            throw ParquetQueryError(message: "Could not connect to DuckDB")
        }
        self.database = database
        self.connection = connection
    }

    deinit {
        var connection: duckdb_connection? = connection
        var database: duckdb_database? = database
        duckdb_disconnect(&connection)
        duckdb_close(&database)
    }

    func interrupt() {
        // Interrupt must bypass the query lock and run from another thread.
        duckdb_interrupt(connection)
    }

    func query(_ sql: String, bindings: [Binding] = [], resultRowLimit: Int? = ParquetPage.rowLimit) throws -> [[String?]] {
        queryLock.lock()
        defer { queryLock.unlock() }
        var statement: duckdb_prepared_statement?
        let status = duckdb_prepare(connection, sql, &statement)
        defer { duckdb_destroy_prepare(&statement) }
        guard status == DuckDBSuccess else {
            throw ParquetQueryError(message: duckdb_prepare_error(statement).map { String(cString: $0) } ?? "Prepare failed")
        }
        for (offset, binding) in bindings.enumerated() {
            let index = idx_t(offset + 1)
            let status: duckdb_state
            switch binding {
            case .text(let value):
                status = value.withCString { duckdb_bind_varchar_length(statement, index, $0, idx_t(value.utf8.count)) }
            case .integer(let value):
                status = duckdb_bind_int64(statement, index, value)
            }
            guard status == DuckDBSuccess else { throw ParquetQueryError(message: "Binding failed") }
        }
        var result = duckdb_result()
        let execution = duckdb_execute_prepared(statement, &result)
        defer { duckdb_destroy_result(&result) }
        guard execution == DuckDBSuccess else {
            throw ParquetQueryError(
                message: duckdb_result_error(&result).map { String(cString: $0) } ?? "Query failed",
                interrupted: duckdb_result_error_type(&result) == DUCKDB_ERROR_INTERRUPT
            )
        }
        if let resultRowLimit, duckdb_row_count(&result) > resultRowLimit {
            throw ParquetQueryError(message: "Queries must return at most \(resultRowLimit.localizedCount) rows")
        }
        return try (0..<duckdb_row_count(&result)).map { row in
            try (0..<duckdb_column_count(&result)).map { column in
                if duckdb_value_is_null(&result, column, row) { return nil }
                guard let value = duckdb_value_varchar(&result, column, row) else {
                    throw ParquetQueryError(message: "Could not convert query result")
                }
                defer { duckdb_free(value) }
                return String(cString: value)
            }
        }
    }
}
