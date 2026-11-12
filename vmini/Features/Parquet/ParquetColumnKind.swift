import Foundation

enum ParquetColumnKind: Sendable {
    case text, number, date, boolean, other

    init(type: String) {
        switch type {
        case "VARCHAR", "CHAR", "TEXT", "UUID": self = .text
        case "BOOLEAN": self = .boolean
        case "TINYINT", "SMALLINT", "INTEGER", "BIGINT", "HUGEINT", "UTINYINT", "USMALLINT",
             "UINTEGER", "UBIGINT", "UHUGEINT", "FLOAT", "DOUBLE", "REAL": self = .number
        case "DATE", "TIME", "TIME WITH TIME ZONE", "TIMESTAMP", "TIMESTAMP_S", "TIMESTAMP_MS",
             "TIMESTAMP_NS", "TIMESTAMP WITH TIME ZONE": self = .date
        default: self = type.range(of: #"^DECIMAL\([0-9]{1,2},[0-9]{1,2}\)$"#, options: .regularExpression) != nil ? .number : .other
        }
    }

    var operators: [ParquetQuery.Operator] {
        switch self {
        case .text: return [.contains, .equals, .startsWith, .isNull, .isNotNull]
        case .number: return [.equals, .notEquals, .greater, .less, .greaterEqual, .lessEqual, .isNull, .isNotNull]
        case .date: return [.equals, .greater, .less, .isNull, .isNotNull]
        case .boolean: return [.any, .isTrue, .isFalse, .isNull, .isNotNull]
        case .other: return [.any, .isNull, .isNotNull]
        }
    }

    func title(for operation: ParquetQuery.Operator) -> String {
        if self == .number && operation == .equals { return "=" }
        if self == .date {
            switch operation {
            case .equals: return "On"
            case .greater: return "After"
            case .less: return "Before"
            default: break
            }
        }
        return operation.rawValue
    }
}
