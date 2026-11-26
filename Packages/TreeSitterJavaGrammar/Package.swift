// swift-tools-version: 5.9
import PackageDescription

// Vendored from tree-sitter-java v0.23.5 (94703d5): src/parser.c, src/tree_sitter/, queries/highlights.scm.
// Upstream's package can't be used directly: TreeSitterLanguages already declares a TreeSitterJava target.
let package = Package(
    name: "TreeSitterJavaGrammar",
    products: [
        .library(name: "TreeSitterJavaGrammar", targets: ["TreeSitterJavaGrammar"]),
        .library(name: "TreeSitterJavaGrammarQueries", targets: ["TreeSitterJavaGrammarQueries"]),
    ],
    targets: [
        .target(name: "TreeSitterJavaGrammar", cSettings: [.headerSearchPath(".")]),
        .target(name: "TreeSitterJavaGrammarQueries", resources: [.copy("highlights.scm")]),
    ],
    cLanguageStandard: .c11
)
