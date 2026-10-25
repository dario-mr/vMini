import AppKit

@MainActor
final class YAMLSyntaxHighlighter: TreeSitterSyntaxHighlighter {
    init() { super.init(language: .yaml) }
}
