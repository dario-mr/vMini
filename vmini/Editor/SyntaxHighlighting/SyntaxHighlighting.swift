import AppKit
import UniformTypeIdentifiers

enum SyntaxLanguage: String {
    case plaintext
    case markdown
}

enum SyntaxLanguageResolver {
    private static let fileExtensionMap: [String: SyntaxLanguage] = [
        "md": .markdown,
        "markdown": .markdown,
    ]

    static func resolve(fileURL: URL?, typeIdentifier: String?) -> SyntaxLanguage {
        if let fileExtension = fileURL?.pathExtension.lowercased(),
           let language = fileExtensionMap[fileExtension] {
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

        return fileExtensionMap[normalized]
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

    static let `default` = SyntaxTheme(
        plainText: AppColors.primaryText,
        headingMarker: NSColor(calibratedRed: 0.96, green: 0.37, blue: 0.41, alpha: 1.0),
        headingText: NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: 1.0),
        listMarker: NSColor(calibratedRed: 0.98, green: 0.69, blue: 0.31, alpha: 1.0),
        blockquoteMarker: NSColor(calibratedRed: 0.47, green: 0.78, blue: 0.88, alpha: 1.0),
        inlineCode: NSColor(calibratedRed: 0.78, green: 0.56, blue: 0.86, alpha: 1.0),
        codeFence: NSColor(calibratedRed: 0.42, green: 0.79, blue: 0.84, alpha: 1.0),
        codeBlockBackground: NSColor(white: 1.0, alpha: 0.08),
        linkText: NSColor(calibratedRed: 0.45, green: 0.71, blue: 0.96, alpha: 1.0),
        linkURL: NSColor(calibratedRed: 0.53, green: 0.89, blue: 0.67, alpha: 1.0),
        emphasisMarker: NSColor(calibratedRed: 0.97, green: 0.64, blue: 0.30, alpha: 1.0),
        thematicBreak: NSColor(calibratedRed: 0.73, green: 0.77, blue: 0.80, alpha: 1.0)
    )

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
            MarkdownSyntaxHighlighter(),
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
