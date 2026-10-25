import AppKit

@MainActor
final class DotenvSyntaxHighlighter: TreeSitterSyntaxHighlighter {
    init() { super.init(language: .dotenv) }
}
