import Foundation

enum SyntaxLanguage: String, CaseIterable {
    case plaintext
    case markdown
    case bash
    case dotenv
    case sshconfig
    case json
    case yaml
    case kotlin

    var displayName: String {
        switch self {
        case .plaintext:
            "Plain Text"
        case .markdown:
            "Markdown"
        case .bash:
            "Bash"
        case .dotenv:
            "Dotenv"
        case .sshconfig:
            "SSH Config"
        case .json:
            "JSON"
        case .yaml:
            "YAML"
        case .kotlin:
            "Kotlin"
        }
    }
}
