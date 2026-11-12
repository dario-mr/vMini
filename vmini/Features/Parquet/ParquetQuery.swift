import Foundation

struct ParquetQuery: Equatable, Sendable {
    enum Operator: String, Sendable {
        case contains = "Contains", equals = "Equals", notEquals = "≠", startsWith = "Starts with"
        case greater = ">", less = "<", greaterEqual = "≥", lessEqual = "≤"
        case isNull = "Is NULL", isNotNull = "Not NULL", any = "Any", isTrue = "True", isFalse = "False"

        var needsValue: Bool { ![.isNull, .isNotNull, .any, .isTrue, .isFalse].contains(self) }
    }

    struct Filter: Equatable, Sendable {
        var operation: Operator
        var value = ""
    }

    struct Sort: Equatable, Sendable {
        let column: ParquetPage.Column
        var ascending = true
    }

    var search = ""
    var filters: [ParquetPage.Column: Filter] = [:]
    var sort: Sort?
    var isFiltered: Bool { !search.isEmpty || !filters.isEmpty }

    mutating func cycleSort(column: ParquetPage.Column) {
        if sort?.column != column { sort = Sort(column: column) }
        else if sort?.ascending == true { sort?.ascending = false }
        else { sort = nil }
    }

    func compatible(with columns: [ParquetPage.Column]) -> Self {
        var query = self
        query.filters = filters.filter { columns.contains($0.key) }
        if let sort, !columns.contains(sort.column) { query.sort = nil }
        return query
    }

    struct SQL {
        let predicate: String
        let bindings: [ParquetConnection.Binding]
        let rows: String
    }

    func sql(columns: [ParquetPage.Column], connection: ParquetConnection) throws -> SQL {
        guard compatible(with: columns) == self else {
            throw ParquetQueryError(message: "A selected column is no longer available.")
        }
        var predicates: [String] = []
        var bindings: [ParquetConnection.Binding] = []
        if !search.isEmpty {
            predicates.append("(" + columns.map {
                bindings.append(.text(search))
                return "contains(lower(CAST(\(Self.identifier($0.name)) AS VARCHAR)), lower(?))"
            }.joined(separator: " OR ") + ")")
        }
        for column in columns {
            guard let filter = filters[column] else { continue }
            let kind = ParquetColumnKind(type: column.type)
            guard kind.operators.contains(filter.operation), filter.operation != .any else {
                throw ParquetQueryError(message: "This filter is not supported for \(column.name).")
            }
            let name = Self.identifier(column.name)
            switch filter.operation {
            case .isNull: predicates.append("\(name) IS NULL")
            case .isNotNull: predicates.append("\(name) IS NOT NULL")
            case .isTrue: predicates.append("\(name) IS TRUE")
            case .isFalse: predicates.append("\(name) IS FALSE")
            case .contains, .startsWith:
                let function = filter.operation == .contains ? "contains" : "starts_with"
                predicates.append("\(function)(lower(CAST(\(name) AS VARCHAR)), lower(?))")
                bindings.append(.text(filter.value))
            default:
                let comparison: String
                switch filter.operation {
                case .greater: comparison = ">"
                case .less: comparison = "<"
                case .greaterEqual: comparison = ">="
                case .lessEqual: comparison = "<="
                case .notEquals: comparison = "<>"
                default: comparison = "="
                }
                if kind == .text {
                    predicates.append("CAST(\(name) AS VARCHAR) = ?")
                } else {
                    let type = try Self.comparisonType(column: column, value: filter.value)
                    do { _ = try connection.query("SELECT CAST(? AS \(type))", bindings: [.text(filter.value)]) }
                    catch { throw ParquetQueryError(message: "Enter a valid \(type) value for ‘\(column.name)’.") }
                    let expression = type == "DATE" ? "CAST(\(name) AS DATE)" : name
                    predicates.append("\(expression) \(comparison) CAST(? AS \(type))")
                }
                bindings.append(.text(filter.value))
            }
        }
        let predicate = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
        // The C API cannot read lists, structs, maps or blobs as text, so cast them in SQL.
        let projection = columns.map { column in
            let name = Self.identifier(column.name)
            return ParquetColumnKind(type: column.type) == .other ? "CAST(\(name) AS VARCHAR) AS \(name)" : name
        }.joined(separator: ", ")
        if let sort, ParquetColumnKind(type: sort.column.type) == .other {
            throw ParquetQueryError(message: "Sorting is not supported for \(sort.column.name).")
        }
        let rows: String
        if sort == nil && predicates.isEmpty {
            rows = "SELECT \(projection) FROM read_parquet(?) LIMIT \(ParquetPage.rowLimit)"
        } else {
            var ordinal = "__vmini_row_order"
            while columns.contains(where: { $0.name.caseInsensitiveCompare(ordinal) == .orderedSame }) { ordinal += "_" }
            let fileOrder = Self.identifier(ordinal)
            let sortOrder = sort.map { "\(Self.identifier($0.column.name)) \($0.ascending ? "ASC" : "DESC") NULLS LAST, " } ?? ""
            // An explicit ORDER BY … LIMIT keeps memory bounded: a plain filtered LIMIT makes DuckDB buffer every
            // sparse batch to preserve file order. File order breaks ties.
            if columns.contains(where: { $0.name.caseInsensitiveCompare("file_row_number") == .orderedSame }) {
                rows = "WITH source AS (SELECT *, row_number() OVER () AS \(fileOrder) FROM read_parquet(?)) "
                    + "SELECT \(projection) FROM source\(predicate) ORDER BY \(sortOrder)\(fileOrder) LIMIT \(ParquetPage.rowLimit)"
            } else {
                // Rank only the sort key and row number, then read full rows for the winners: sorting whole rows
                // of wide files exhausted memory, and the parallel row number is far faster than a window function.
                rows = "WITH source AS (SELECT * FROM read_parquet(?, file_row_number = true)), "
                    + "top AS (SELECT file_row_number AS \(fileOrder) FROM source\(predicate) "
                    + "ORDER BY \(sortOrder)file_row_number LIMIT \(ParquetPage.rowLimit)) "
                    + "SELECT \(projection) FROM source JOIN top ON source.file_row_number = top.\(fileOrder) "
                    + "ORDER BY \(sortOrder)source.file_row_number"
            }
        }
        return SQL(predicate: predicate, bindings: bindings, rows: rows)
    }

    private static func identifier(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    private static func comparisonType(column: ParquetPage.Column, value: String) throws -> String {
        let type = column.type
        let kind = ParquetColumnKind(type: type)
        if kind == .date { return type.hasPrefix("TIME") && !type.hasPrefix("TIMESTAMP") ? type : "DATE" }
        if ["FLOAT", "DOUBLE", "REAL"].contains(type) { return type }
        let valid: Bool
        if type.hasPrefix("DECIMAL(") {
            let scale = Int(type.dropLast().split(separator: ",").last ?? "") ?? 0
            let fraction = value.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
            valid = value.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil && fraction <= scale
        } else {
            valid = value.range(of: #"^[+-]?[0-9]+$"#, options: .regularExpression) != nil
        }
        guard kind == .number, valid else {
            throw ParquetQueryError(message: "Enter a valid \(type) value for ‘\(column.name)’ without rounding.")
        }
        return type
    }
}
