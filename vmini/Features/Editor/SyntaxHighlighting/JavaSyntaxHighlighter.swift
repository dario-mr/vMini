import AppKit

@MainActor
final class JavaSyntaxHighlighter: TreeSitterSyntaxHighlighter {
    init() { super.init(language: .java) }
}
