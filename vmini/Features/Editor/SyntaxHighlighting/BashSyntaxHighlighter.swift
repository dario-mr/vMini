import AppKit

@MainActor
final class BashSyntaxHighlighter: TreeSitterSyntaxHighlighter {
    init() { super.init(language: .bash) }
}
