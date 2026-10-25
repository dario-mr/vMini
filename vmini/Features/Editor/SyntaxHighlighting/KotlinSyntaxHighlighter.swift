import AppKit

@MainActor
final class KotlinSyntaxHighlighter: TreeSitterSyntaxHighlighter {
    init() { super.init(language: .kotlin) }
}
