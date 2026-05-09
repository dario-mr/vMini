import AppKit
import UniformTypeIdentifiers

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

enum SyntaxLanguageResolver {
    private static let shellFileExtensionMap: [String: SyntaxLanguage] = [
        "sh": .bash,
        "bash": .bash,
        "zsh": .bash,
    ]

    private static let markdownFileExtensionMap: [String: SyntaxLanguage] = [
        "md": .markdown,
        "markdown": .markdown,
    ]

    private static let jsonFileExtensionMap: [String: SyntaxLanguage] = [
        "json": .json,
    ]

    private static let fileNameMap: [String: SyntaxLanguage] = [
        "config": .sshconfig,
        ".zshenv": .bash,
        ".zprofile": .bash,
        ".zshrc": .bash,
        ".bashrc": .bash,
        ".bash_profile": .bash,
        ".profile": .bash,
        ".bash_logout": .bash,
    ]

    private static let fenceInfoStringMap: [String: SyntaxLanguage] = [
        "sh": .bash,
        "bash": .bash,
        "zsh": .bash,
        "shell": .bash,
        "md": .markdown,
        "markdown": .markdown,
        "json": .json,
    ]

    static func resolve(fileURL: URL?, typeIdentifier: String?, content: String? = nil) -> SyntaxLanguage {
        if let fileExtension = fileURL?.pathExtension.lowercased(),
           let language = shellFileExtensionMap[fileExtension] {
            return language
        }

        if let fileName = fileURL?.lastPathComponent.lowercased(),
           let language = fileNameMap[fileName] {
            return language
        }

        if hasShellShebang(in: content) {
            return .bash
        }

        if let fileExtension = fileURL?.pathExtension.lowercased(),
           let language = jsonFileExtensionMap[fileExtension] {
            return language
        }

        if let fileExtension = fileURL?.pathExtension.lowercased(),
           let language = markdownFileExtensionMap[fileExtension] {
            return language
        }

        if let typeIdentifier, let type = UTType(typeIdentifier) {
            if type.conforms(to: .plainText) || type.conforms(to: .text) {
                return .plaintext
            }
        }

        return .plaintext
    }

    static func resolveFenceInfoString(_ infoString: String) -> SyntaxLanguage? {
        let normalized = infoString
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased()

        guard let normalized else {
            return nil
        }

        return fenceInfoStringMap[normalized]
    }

    private static func hasShellShebang(in content: String?) -> Bool {
        guard let content else {
            return false
        }

        let firstLine = content
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            .split(whereSeparator: \.isNewline)
            .first?
            .lowercased()

        guard let firstLine, firstLine.hasPrefix("#!") else {
            return false
        }

        let tokens = firstLine
            .split(whereSeparator: { $0.isWhitespace || $0 == "/" })
            .map(String.init)

        return tokens.contains("sh") || tokens.contains("bash") || tokens.contains("zsh")
    }
}

enum SyntaxColorRole {
    case plainText
    case headingMarker
    case headingText
    case listMarker
    case blockquoteMarker
    case inlineCode
    case codeFence
    case codeBlockBackground
    case linkText
    case linkURL
    case emphasisMarker
    case thematicBreak
    case comment
    case string
    case variable
    case keyword
    case `operator`
    case builtin
    case propertyKey
}

struct SyntaxTheme {
    let plainText: NSColor
    let headingMarker: NSColor
    let headingText: NSColor
    let listMarker: NSColor
    let blockquoteMarker: NSColor
    let inlineCode: NSColor
    let codeFence: NSColor
    let codeBlockBackground: NSColor
    let linkText: NSColor
    let linkURL: NSColor
    let emphasisMarker: NSColor
    let thematicBreak: NSColor
    let comment: NSColor
    let string: NSColor
    let variable: NSColor
    let keyword: NSColor
    let `operator`: NSColor
    let builtin: NSColor
    let propertyKey: NSColor

    func color(for role: SyntaxColorRole) -> NSColor {
        switch role {
        case .plainText:
            plainText
        case .headingMarker:
            headingMarker
        case .headingText:
            headingText
        case .listMarker:
            listMarker
        case .blockquoteMarker:
            blockquoteMarker
        case .inlineCode:
            inlineCode
        case .codeFence:
            codeFence
        case .codeBlockBackground:
            codeBlockBackground
        case .linkText:
            linkText
        case .linkURL:
            linkURL
        case .emphasisMarker:
            emphasisMarker
        case .thematicBreak:
            thematicBreak
        case .comment:
            comment
        case .string:
            string
        case .variable:
            variable
        case .keyword:
            keyword
        case .operator:
            self.operator
        case .builtin:
            builtin
        case .propertyKey:
            propertyKey
        }
    }
}

@MainActor
protocol SyntaxHighlighter {
    var language: SyntaxLanguage { get }

    func expandedHighlightRange(for editedRange: NSRange, in text: NSString) -> NSRange
    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    )
}

@MainActor
final class HighlighterRegistry {
    static let shared = HighlighterRegistry()

    private let highlighters: [SyntaxLanguage: SyntaxHighlighter]

    init(highlighters: [SyntaxHighlighter]? = nil) {
        let resolvedHighlighters = highlighters ?? [
            PlainTextSyntaxHighlighter(),
            BashSyntaxHighlighter(),
            SSHConfigSyntaxHighlighter(),
            MarkdownSyntaxHighlighter(),
            JSONSyntaxHighlighter(),
        ]
        self.highlighters = Dictionary(uniqueKeysWithValues: resolvedHighlighters.map { ($0.language, $0) })
    }

    func highlighter(for language: SyntaxLanguage) -> SyntaxHighlighter {
        highlighters[language] ?? PlainTextSyntaxHighlighter()
    }

    func highlighter(forFenceInfoString infoString: String) -> SyntaxHighlighter? {
        guard let language = SyntaxLanguageResolver.resolveFenceInfoString(infoString) else {
            return nil
        }

        return highlighters[language]
    }
}

extension NSRange {
    func clamped(toLength length: Int) -> NSRange {
        let safeLocation = min(max(location, 0), length)
        let safeLength = min(max(self.length, 0), max(length - safeLocation, 0))
        return NSRange(location: safeLocation, length: safeLength)
    }

    func intersects(_ other: NSRange) -> Bool {
        NSIntersectionRange(self, other).length > 0
    }

    var upperBound: Int {
        NSMaxRange(self)
    }
}

extension NSTextStorage {
    func applyForegroundColor(_ color: NSColor, range: NSRange) {
        guard range.length > 0 else { return }
        addAttribute(.foregroundColor, value: color, range: range)
    }

    func applyBackgroundColor(_ color: NSColor?, range: NSRange) {
        guard range.length > 0 else { return }
        if let color {
            addAttribute(.backgroundColor, value: color, range: range)
        } else {
            removeAttribute(.backgroundColor, range: range)
        }
    }
}
