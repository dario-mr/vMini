import DuckDB
import Foundation

enum ParquetTestFixtures {
    static func generate(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try Database(store: .inMemory)
        let connection = try database.connect()
        try connection.execute("SET autoinstall_known_extensions = false; SET autoload_known_extensions = false")
        try connection.execute("""
            CREATE TABLE scalars AS SELECT
                i::BIGINT AS id,
                CASE i WHEN 0 THEN NULL WHEN 1 THEN '' WHEN 2 THEN '00123'
                    WHEN 3 THEN 'NULL' ELSE 'quote '' %_ \\ 雪' END AS label,
                (CASE WHEN i = 0 THEN NULL ELSE 90071992547409.1234 END)::DECIMAL(20,4) AS amount,
                (CASE WHEN i = 0 THEN NULL ELSE i / 3.0 END)::DOUBLE AS ratio,
                CASE WHEN i = 0 THEN NULL ELSE i % 2 = 0 END AS enabled,
                CASE WHEN i = 0 THEN NULL ELSE DATE '2024-02-29' END AS day,
                CASE WHEN i = 0 THEN NULL ELSE TIME '12:34:56.123456' END AS time,
                CASE WHEN i = 0 THEN NULL ELSE TIMESTAMP '2024-02-29 12:34:56.123456' END AS stamp,
                CASE WHEN i = 0 THEN NULL ELSE 9007199254740993 + i END::BIGINT AS "sort ""雪"
            FROM range(6) t(i)
            """)
        for codec in ["snappy", "gzip", "zstd", "uncompressed"] {
            let path = directory.appendingPathComponent("scalars.\(codec).parquet").path
            try connection.execute("COPY scalars TO \(literal(path)) (FORMAT PARQUET, COMPRESSION \(codec))")
        }
    }

    private static func literal(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
