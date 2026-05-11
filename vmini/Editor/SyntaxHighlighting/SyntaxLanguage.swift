import Foundation

enum SyntaxLanguage: String, CaseIterable {
    case plaintext
    case markdown
    case bash
    case sshconfig
    case json

    var displayName: String {
        switch self {
        case .plaintext:
            "Plain Text"
        case .markdown:
            "Markdown"
        case .bash:
            "Bash"
        case .sshconfig:
            "SSH Config"
        case .json:
            "JSON"
        }
    }
}
