import AppKit

@MainActor
final class SQLSyntaxHighlighter: TreeSitterSyntaxHighlighter {
    init() { super.init(language: .sql) }
}
