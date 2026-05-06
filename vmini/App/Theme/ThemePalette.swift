import AppKit

enum ThemeID: String, CaseIterable {
    case `default` = "default"
    case absolutely = "absolutely"
    case dracula = "dracula"

    var displayName: String {
        switch self {
        case .default:
            "Slate"
        case .absolutely:
            "Absolutely"
        case .dracula:
            "Dracula"
        }
    }
}

struct ThemePalette {
    let appBackground: NSColor
    let windowBackground: NSColor
    let editorBackground: NSColor
    let tabBarBackground: NSColor
    let hoveredTabBackground: NSColor

    let primaryText: NSColor
    let sidebarText: NSColor
    let folderSidebarText: NSColor
    let sidebarHeaderText: NSColor
    let inactiveTabText: NSColor
    let lineNumberText: NSColor

    let activeControlTint: NSColor
    let defaultControlTint: NSColor
    let hoveredControlTint: NSColor
    let inactiveControlTint: NSColor
    let primaryActionBackground: NSColor
    let primaryActionText: NSColor

    let subtleSelectionFill: NSColor

    let syntaxHeadingMarker: NSColor
    let syntaxHeadingText: NSColor
    let syntaxListMarker: NSColor
    let syntaxBlockquoteMarker: NSColor
    let syntaxInlineCode: NSColor
    let syntaxCodeFence: NSColor
    let syntaxCodeBlockBackground: NSColor
    let syntaxLinkText: NSColor
    let syntaxLinkURL: NSColor
    let syntaxEmphasisMarker: NSColor
    let syntaxThematicBreak: NSColor

    var syntaxTheme: SyntaxTheme {
        SyntaxTheme(
            plainText: primaryText,
            headingMarker: syntaxHeadingMarker,
            headingText: syntaxHeadingText,
            listMarker: syntaxListMarker,
            blockquoteMarker: syntaxBlockquoteMarker,
            inlineCode: syntaxInlineCode,
            codeFence: syntaxCodeFence,
            codeBlockBackground: syntaxCodeBlockBackground,
            linkText: syntaxLinkText,
            linkURL: syntaxLinkURL,
            emphasisMarker: syntaxEmphasisMarker,
            thematicBreak: syntaxThematicBreak
        )
    }
}

enum ThemeCatalog {
    static func palette(for themeID: ThemeID) -> ThemePalette {
        switch themeID {
        case .default:
            ThemePalette(
                appBackground: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.13, alpha: 1.0),
                windowBackground: NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.17, alpha: 1.0),
                editorBackground: NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.20, alpha: 1.0),
                tabBarBackground: NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.28, alpha: 1.0),
                hoveredTabBackground: NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.20, alpha: 0.55),
                primaryText: NSColor(white: 0.98, alpha: 1.0),
                sidebarText: NSColor(white: 0.88, alpha: 1.0),
                folderSidebarText: NSColor(white: 0.86, alpha: 1.0),
                sidebarHeaderText: NSColor(white: 0.84, alpha: 1.0),
                inactiveTabText: NSColor(white: 0.77, alpha: 1.0),
                lineNumberText: NSColor(white: 0.62, alpha: 1.0),
                activeControlTint: NSColor(white: 0.80, alpha: 1.0),
                defaultControlTint: NSColor(white: 0.70, alpha: 1.0),
                hoveredControlTint: NSColor(white: 0.74, alpha: 1.0),
                inactiveControlTint: NSColor(white: 0.62, alpha: 1.0),
                primaryActionBackground: NSColor(calibratedRed: 0.23, green: 0.46, blue: 0.72, alpha: 1.0),
                primaryActionText: NSColor(white: 0.98, alpha: 1.0),
                subtleSelectionFill: NSColor(white: 1.0, alpha: 0.09),
                syntaxHeadingMarker: NSColor(calibratedRed: 0.96, green: 0.37, blue: 0.41, alpha: 1.0),
                syntaxHeadingText: NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: 1.0),
                syntaxListMarker: NSColor(calibratedRed: 0.98, green: 0.69, blue: 0.31, alpha: 1.0),
                syntaxBlockquoteMarker: NSColor(calibratedRed: 0.47, green: 0.78, blue: 0.88, alpha: 1.0),
                syntaxInlineCode: NSColor(calibratedRed: 0.78, green: 0.56, blue: 0.86, alpha: 1.0),
                syntaxCodeFence: NSColor(calibratedRed: 0.42, green: 0.79, blue: 0.84, alpha: 1.0),
                syntaxCodeBlockBackground: NSColor(white: 1.0, alpha: 0.08),
                syntaxLinkText: NSColor(calibratedRed: 0.45, green: 0.71, blue: 0.96, alpha: 1.0),
                syntaxLinkURL: NSColor(calibratedRed: 0.53, green: 0.89, blue: 0.67, alpha: 1.0),
                syntaxEmphasisMarker: NSColor(calibratedRed: 0.97, green: 0.64, blue: 0.30, alpha: 1.0),
                syntaxThematicBreak: NSColor(calibratedRed: 0.73, green: 0.77, blue: 0.80, alpha: 1.0)
            )
        case .absolutely:
            ThemePalette(
                appBackground: NSColor(hex: 0x252523),
                windowBackground: NSColor(hex: 0x2D2D2B),
                editorBackground: NSColor(hex: 0x242423),
                tabBarBackground: NSColor(hex: 0x353533),
                hoveredTabBackground: NSColor(hex: 0xCC7D5E, alpha: 0.22),
                primaryText: NSColor(hex: 0xF9F9F7),
                sidebarText: NSColor(hex: 0xECECE8),
                folderSidebarText: NSColor(hex: 0xE3E3DE),
                sidebarHeaderText: NSColor(hex: 0xD2D2CB),
                inactiveTabText: NSColor(hex: 0xB8B8B1),
                lineNumberText: NSColor(hex: 0x8F8F87),
                activeControlTint: NSColor(hex: 0xF9F9F7),
                defaultControlTint: NSColor(hex: 0xD2D2CB),
                hoveredControlTint: NSColor(hex: 0xCC7D5E),
                inactiveControlTint: NSColor(hex: 0x96968F),
                primaryActionBackground: NSColor(hex: 0xCC7D5E),
                primaryActionText: NSColor(hex: 0xF9F9F7),
                subtleSelectionFill: NSColor(hex: 0xF9F9F7, alpha: 0.08),
                syntaxHeadingMarker: NSColor(hex: 0xCC7D5E),
                syntaxHeadingText: NSColor(hex: 0xF9F9F7),
                syntaxListMarker: NSColor(hex: 0xCC7D5E),
                syntaxBlockquoteMarker: NSColor(hex: 0xCC7D5E, alpha: 0.85),
                syntaxInlineCode: NSColor(hex: 0xF2C6B5),
                syntaxCodeFence: NSColor(hex: 0xCC7D5E),
                syntaxCodeBlockBackground: NSColor(hex: 0xF9F9F7, alpha: 0.05),
                syntaxLinkText: NSColor(hex: 0xCC7D5E),
                syntaxLinkURL: NSColor(hex: 0x00C853),
                syntaxEmphasisMarker: NSColor(hex: 0xCC7D5E),
                syntaxThematicBreak: NSColor(hex: 0x5C5C58)
            )
        case .dracula:
            ThemePalette(
                appBackground: NSColor(hex: 0x23252F),
                windowBackground: NSColor(hex: 0x282A36),
                editorBackground: NSColor(hex: 0x282A36),
                tabBarBackground: NSColor(hex: 0x44475A),
                hoveredTabBackground: NSColor(hex: 0xBD93F9, alpha: 0.22),
                primaryText: NSColor(hex: 0xF8F8F2),
                sidebarText: NSColor(hex: 0xF8F8F2, alpha: 0.92),
                folderSidebarText: NSColor(hex: 0xF8F8F2, alpha: 0.88),
                sidebarHeaderText: NSColor(hex: 0xF8F8F2, alpha: 0.78),
                inactiveTabText: NSColor(hex: 0xF8F8F2, alpha: 0.70),
                lineNumberText: NSColor(hex: 0x6272A4),
                activeControlTint: NSColor(hex: 0xF8F8F2),
                defaultControlTint: NSColor(hex: 0xF8F8F2, alpha: 0.74),
                hoveredControlTint: NSColor(hex: 0xFF79C6),
                inactiveControlTint: NSColor(hex: 0x6272A4),
                primaryActionBackground: NSColor(hex: 0xBD93F9),
                primaryActionText: NSColor(hex: 0x282A36),
                subtleSelectionFill: NSColor(hex: 0x44475A, alpha: 0.85),
                syntaxHeadingMarker: NSColor(hex: 0xFF79C6),
                syntaxHeadingText: NSColor(hex: 0xF8F8F2),
                syntaxListMarker: NSColor(hex: 0xFFB86C),
                syntaxBlockquoteMarker: NSColor(hex: 0x8BE9FD),
                syntaxInlineCode: NSColor(hex: 0xF1FA8C),
                syntaxCodeFence: NSColor(hex: 0x8BE9FD),
                syntaxCodeBlockBackground: NSColor(hex: 0x44475A, alpha: 0.42),
                syntaxLinkText: NSColor(hex: 0x8BE9FD),
                syntaxLinkURL: NSColor(hex: 0x50FA7B),
                syntaxEmphasisMarker: NSColor(hex: 0xFF79C6),
                syntaxThematicBreak: NSColor(hex: 0x6272A4)
            )
        }
    }
}

private extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
