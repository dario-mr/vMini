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
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-ssh-config", exact: "0.5.0"),
        .package(url: "https://github.com/fwcd/tree-sitter-kotlin", exact: "0.3.8"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages", exact: "0.1.10"),
    ],
    targets: [
        .executableTarget(
            name: "vmini",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterBash", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJSON", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdown", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterMarkdownInline", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSSHConfig", package: "tree-sitter-ssh-config"),
                .product(name: "TreeSitterYAML", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
                .product(name: "TreeSitterJava", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSQL", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterSQLQueries", package: "TreeSitterLanguages"),
                .product(name: "TreeSitterJavaQueries", package: "TreeSitterLanguages"),
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
