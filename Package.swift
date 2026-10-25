// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vmini",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vmini", targets: ["vmini"])
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", exact: "0.23.5"),
    ],
    targets: [
        .executableTarget(
            name: "vmini",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
            ],
            path: "vmini",
            exclude: [
                "Assets.xcassets",
                "Info.plist"
            ]
        ),
        .testTarget(
            name: "vminiTests",
            dependencies: ["vmini"],
            path: "Tests/vminiTests",
            exclude: ["PerformanceCorpus"]
        )
    ]
)
