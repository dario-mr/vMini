// swift-tools-version: 5.9
import PackageDescription

// Swift API vendored from duckdb-swift 1.1.3 (9583f44), linked against DuckDB's prebuilt release
// library instead of compiling the C++ amalgamation. scripts/build-duckdb-zip.sh regenerates the archive.
let package = Package(
    name: "DuckDB",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DuckDB", targets: ["DuckDB"])
    ],
    targets: [
        .target(name: "DuckDB", dependencies: ["Cduckdb"]),
        .binaryTarget(name: "Cduckdb", path: "Cduckdb.xcframework.zip")
    ]
)
