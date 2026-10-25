import AppKit

@MainActor
final class SSHConfigSyntaxHighlighter: TreeSitterSyntaxHighlighter {
    init() { super.init(language: .sshconfig) }
}
