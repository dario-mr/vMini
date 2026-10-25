import AppKit

@MainActor
final class JSONSyntaxHighlighter: TreeSitterSyntaxHighlighter {
    init() { super.init(language: .json) }
}
