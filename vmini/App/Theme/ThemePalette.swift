import AppKit

enum ThemeID: String, CaseIterable {
    case `default` = "default"
    case absolutely = "absolutely"
    case dracula = "dracula"
    case gruvboxDark = "gruvbox-dark"
    case solarizedLight = "solarized-light"
    case nord = "nord"
    case catppuccinMocha = "catppuccin-mocha"

    var displayName: String {
        switch self {
        case .default:
            "Slate"
        case .absolutely:
            "Absolutely"
        case .dracula:
            "Dracula"
        case .gruvboxDark:
            "Gruvbox Dark"
        case .solarizedLight:
            "Solarized Light"
        case .nord:
            "Nord"
        case .catppuccinMocha:
            "Catppuccin Mocha"
        }
    }

    var preferredAppearance: NSAppearance.Name {
        switch self {
        case .solarizedLight:
            .aqua
        default:
            .darkAqua
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
    let syntaxComment: NSColor
    let syntaxString: NSColor
    let syntaxVariable: NSColor
    let syntaxKeyword: NSColor
    let syntaxOperator: NSColor
    let syntaxBuiltin: NSColor
    let syntaxPropertyKey: NSColor

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
            thematicBreak: syntaxThematicBreak,
            comment: syntaxComment,
            string: syntaxString,
            variable: syntaxVariable,
            keyword: syntaxKeyword,
            operator: syntaxOperator,
            builtin: syntaxBuiltin,
            propertyKey: syntaxPropertyKey
        )
    }
}

enum ThemeCatalog {
    static func palette(for themeID: ThemeID) -> ThemePalette {
        switch themeID {
        case .default:
            ThemePalette(
                appBackground: NSColor(hex: 0x141C21),
                windowBackground: NSColor(hex: 0x1C242B),
                editorBackground: NSColor(hex: 0x142933),
                tabBarBackground: NSColor(hex: 0x333D47),
                hoveredTabBackground: NSColor(hex: 0x142933, alpha: 0.55),
                primaryText: NSColor(hex: 0xFAFAFA),
                sidebarText: NSColor(hex: 0xE0E0E0),
                folderSidebarText: NSColor(hex: 0xDBDBDB),
                sidebarHeaderText: NSColor(hex: 0xD6D6D6),
                inactiveTabText: NSColor(hex: 0xC4C4C4),
                lineNumberText: NSColor(hex: 0x9E9E9E),
                activeControlTint: NSColor(hex: 0xCCCCCC),
                defaultControlTint: NSColor(hex: 0xB3B3B3),
                hoveredControlTint: NSColor(hex: 0xBDBDBD),
                inactiveControlTint: NSColor(hex: 0x9E9E9E),
                primaryActionBackground: NSColor(hex: 0x3B75B8),
                primaryActionText: NSColor(hex: 0xFAFAFA),
                subtleSelectionFill: NSColor(hex: 0xFFFFFF, alpha: 0.09),
                syntaxHeadingMarker: NSColor(hex: 0xF55E69),
                syntaxHeadingText: NSColor(hex: 0xFAB0B8),
                syntaxListMarker: NSColor(hex: 0xFAB04F),
                syntaxBlockquoteMarker: NSColor(hex: 0x78C7E0),
                syntaxInlineCode: NSColor(hex: 0xC78FDB),
                syntaxCodeFence: NSColor(hex: 0x6BC9D6),
                syntaxCodeBlockBackground: NSColor(hex: 0xFFFFFF, alpha: 0.08),
                syntaxLinkText: NSColor(hex: 0x73B5F5),
                syntaxLinkURL: NSColor(hex: 0x87E3AB),
                syntaxEmphasisMarker: NSColor(hex: 0xF7A34D),
                syntaxThematicBreak: NSColor(hex: 0xBAC4CC),
                syntaxComment: NSColor(hex: 0x75949E),
                syntaxString: NSColor(hex: 0x8FD6AB),
                syntaxVariable: NSColor(hex: 0xC4B0F2),
                syntaxKeyword: NSColor(hex: 0xF55E69),
                syntaxOperator: NSColor(hex: 0x91D4EB),
                syntaxBuiltin: NSColor(hex: 0xFAB04F),
                syntaxPropertyKey: NSColor(hex: 0xFAB04F)
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
                syntaxHeadingText: NSColor(hex: 0xE8A58B),
                syntaxListMarker: NSColor(hex: 0xCC7D5E),
                syntaxBlockquoteMarker: NSColor(hex: 0xCC7D5E, alpha: 0.85),
                syntaxInlineCode: NSColor(hex: 0xF2C6B5),
                syntaxCodeFence: NSColor(hex: 0xCC7D5E),
                syntaxCodeBlockBackground: NSColor(hex: 0xF9F9F7, alpha: 0.05),
                syntaxLinkText: NSColor(hex: 0xCC7D5E),
                syntaxLinkURL: NSColor(hex: 0x00C853),
                syntaxEmphasisMarker: NSColor(hex: 0xCC7D5E),
                syntaxThematicBreak: NSColor(hex: 0x5C5C58),
                syntaxComment: NSColor(hex: 0x8F8F87),
                syntaxString: NSColor(hex: 0xDDE68B),
                syntaxVariable: NSColor(hex: 0xD7B7F6),
                syntaxKeyword: NSColor(hex: 0xD97757),
                syntaxOperator: NSColor(hex: 0xF3E7D4),
                syntaxBuiltin: NSColor(hex: 0xF0B36A),
                syntaxPropertyKey: NSColor(hex: 0xCC7D5E)
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
                primaryActionBackground: NSColor(hex: 0xA277DE),
                primaryActionText: NSColor(white: 0.98, alpha: 1.0),
                subtleSelectionFill: NSColor(hex: 0x44475A, alpha: 0.85),
                syntaxHeadingMarker: NSColor(hex: 0xFF79C6),
                syntaxHeadingText: NSColor(hex: 0xFFB3DA),
                syntaxListMarker: NSColor(hex: 0xFFB86C),
                syntaxBlockquoteMarker: NSColor(hex: 0x8BE9FD),
                syntaxInlineCode: NSColor(hex: 0xF1FA8C),
                syntaxCodeFence: NSColor(hex: 0x8BE9FD),
                syntaxCodeBlockBackground: NSColor(hex: 0x44475A, alpha: 0.42),
                syntaxLinkText: NSColor(hex: 0x8BE9FD),
                syntaxLinkURL: NSColor(hex: 0x50FA7B),
                syntaxEmphasisMarker: NSColor(hex: 0xFF79C6),
                syntaxThematicBreak: NSColor(hex: 0x6272A4),
                syntaxComment: NSColor(hex: 0x8B92B2),
                syntaxString: NSColor(hex: 0xF1FA8C),
                syntaxVariable: NSColor(hex: 0xBD93F9),
                syntaxKeyword: NSColor(hex: 0xFF79C6),
                syntaxOperator: NSColor(hex: 0xFF79C6),
                syntaxBuiltin: NSColor(hex: 0xFFB86C),
                syntaxPropertyKey: NSColor(hex: 0x8BE9FD)
            )
        case .gruvboxDark:
            ThemePalette(
                appBackground: NSColor(hex: 0x1D2021),
                windowBackground: NSColor(hex: 0x282828),
                editorBackground: NSColor(hex: 0x282828),
                tabBarBackground: NSColor(hex: 0x3C3836),
                hoveredTabBackground: NSColor(hex: 0xD79921, alpha: 0.20),
                primaryText: NSColor(hex: 0xEBDBB2),
                sidebarText: NSColor(hex: 0xEBDBB2, alpha: 0.92),
                folderSidebarText: NSColor(hex: 0xD5C4A1),
                sidebarHeaderText: NSColor(hex: 0xBDAE93),
                inactiveTabText: NSColor(hex: 0xA89984),
                lineNumberText: NSColor(hex: 0x7C6F64),
                activeControlTint: NSColor(hex: 0xEBDBB2),
                defaultControlTint: NSColor(hex: 0xD5C4A1),
                hoveredControlTint: NSColor(hex: 0xFABD2F),
                inactiveControlTint: NSColor(hex: 0x928374),
                primaryActionBackground: NSColor(hex: 0x458588),
                primaryActionText: NSColor(hex: 0xFBF1C7),
                subtleSelectionFill: NSColor(hex: 0x504945, alpha: 0.72),
                syntaxHeadingMarker: NSColor(hex: 0xFB4934),
                syntaxHeadingText: NSColor(hex: 0xFABD2F),
                syntaxListMarker: NSColor(hex: 0xFABD2F),
                syntaxBlockquoteMarker: NSColor(hex: 0x83A598),
                syntaxInlineCode: NSColor(hex: 0xD3869B),
                syntaxCodeFence: NSColor(hex: 0x8EC07C),
                syntaxCodeBlockBackground: NSColor(hex: 0x3C3836, alpha: 0.48),
                syntaxLinkText: NSColor(hex: 0x83A598),
                syntaxLinkURL: NSColor(hex: 0x8EC07C),
                syntaxEmphasisMarker: NSColor(hex: 0xFE8019),
                syntaxThematicBreak: NSColor(hex: 0x665C54),
                syntaxComment: NSColor(hex: 0x928374),
                syntaxString: NSColor(hex: 0xB8BB26),
                syntaxVariable: NSColor(hex: 0xD3869B),
                syntaxKeyword: NSColor(hex: 0xFB4934),
                syntaxOperator: NSColor(hex: 0x83A598),
                syntaxBuiltin: NSColor(hex: 0xFE8019),
                syntaxPropertyKey: NSColor(hex: 0x83A598)
            )
        case .solarizedLight:
            ThemePalette(
                appBackground: NSColor(hex: 0xFDF6E3),
                windowBackground: NSColor(hex: 0xEEE8D5),
                editorBackground: NSColor(hex: 0xFDF6E3),
                tabBarBackground: NSColor(hex: 0xE4DDC8),
                hoveredTabBackground: NSColor(hex: 0x268BD2, alpha: 0.14),
                primaryText: NSColor(hex: 0x586E75),
                sidebarText: NSColor(hex: 0x586E75, alpha: 0.94),
                folderSidebarText: NSColor(hex: 0x657B83),
                sidebarHeaderText: NSColor(hex: 0x657B83, alpha: 0.88),
                inactiveTabText: NSColor(hex: 0x839496),
                lineNumberText: NSColor(hex: 0x93A1A1),
                activeControlTint: NSColor(hex: 0x586E75),
                defaultControlTint: NSColor(hex: 0x657B83),
                hoveredControlTint: NSColor(hex: 0x268BD2),
                inactiveControlTint: NSColor(hex: 0x93A1A1),
                primaryActionBackground: NSColor(hex: 0x268BD2),
                primaryActionText: NSColor(hex: 0xFDF6E3),
                subtleSelectionFill: NSColor(hex: 0x93A1A1, alpha: 0.18),
                syntaxHeadingMarker: NSColor(hex: 0xDC322F),
                syntaxHeadingText: NSColor(hex: 0xCB4B16),
                syntaxListMarker: NSColor(hex: 0xB58900),
                syntaxBlockquoteMarker: NSColor(hex: 0x2AA198),
                syntaxInlineCode: NSColor(hex: 0x6C71C4),
                syntaxCodeFence: NSColor(hex: 0x2AA198),
                syntaxCodeBlockBackground: NSColor(hex: 0xEEE8D5, alpha: 0.78),
                syntaxLinkText: NSColor(hex: 0x268BD2),
                syntaxLinkURL: NSColor(hex: 0x859900),
                syntaxEmphasisMarker: NSColor(hex: 0xCB4B16),
                syntaxThematicBreak: NSColor(hex: 0x93A1A1),
                syntaxComment: NSColor(hex: 0x93A1A1),
                syntaxString: NSColor(hex: 0x859900),
                syntaxVariable: NSColor(hex: 0x6C71C4),
                syntaxKeyword: NSColor(hex: 0x268BD2),
                syntaxOperator: NSColor(hex: 0x2AA198),
                syntaxBuiltin: NSColor(hex: 0xCB4B16),
                syntaxPropertyKey: NSColor(hex: 0xCB4B16)
            )
        case .nord:
            ThemePalette(
                appBackground: NSColor(hex: 0x2B303B),
                windowBackground: NSColor(hex: 0x2E3440),
                editorBackground: NSColor(hex: 0x2E3440),
                tabBarBackground: NSColor(hex: 0x3B4252),
                hoveredTabBackground: NSColor(hex: 0x88C0D0, alpha: 0.18),
                primaryText: NSColor(hex: 0xECEFF4),
                sidebarText: NSColor(hex: 0xE5E9F0, alpha: 0.94),
                folderSidebarText: NSColor(hex: 0xD8DEE9),
                sidebarHeaderText: NSColor(hex: 0xD8DEE9, alpha: 0.84),
                inactiveTabText: NSColor(hex: 0xBEC8D9),
                lineNumberText: NSColor(hex: 0x4C566A),
                activeControlTint: NSColor(hex: 0xECEFF4),
                defaultControlTint: NSColor(hex: 0xD8DEE9),
                hoveredControlTint: NSColor(hex: 0x88C0D0),
                inactiveControlTint: NSColor(hex: 0x4C566A),
                primaryActionBackground: NSColor(hex: 0x5E81AC),
                primaryActionText: NSColor(hex: 0xECEFF4),
                subtleSelectionFill: NSColor(hex: 0x434C5E, alpha: 0.82),
                syntaxHeadingMarker: NSColor(hex: 0xBF616A),
                syntaxHeadingText: NSColor(hex: 0xD08770),
                syntaxListMarker: NSColor(hex: 0xEBCB8B),
                syntaxBlockquoteMarker: NSColor(hex: 0x88C0D0),
                syntaxInlineCode: NSColor(hex: 0xB48EAD),
                syntaxCodeFence: NSColor(hex: 0x8FBCBB),
                syntaxCodeBlockBackground: NSColor(hex: 0x3B4252, alpha: 0.58),
                syntaxLinkText: NSColor(hex: 0x88C0D0),
                syntaxLinkURL: NSColor(hex: 0xA3BE8C),
                syntaxEmphasisMarker: NSColor(hex: 0xD08770),
                syntaxThematicBreak: NSColor(hex: 0x4C566A),
                syntaxComment: NSColor(hex: 0x616E88),
                syntaxString: NSColor(hex: 0xA3BE8C),
                syntaxVariable: NSColor(hex: 0xB48EAD),
                syntaxKeyword: NSColor(hex: 0x81A1C1),
                syntaxOperator: NSColor(hex: 0x81A1C1),
                syntaxBuiltin: NSColor(hex: 0xD08770),
                syntaxPropertyKey: NSColor(hex: 0x81A1C1)
            )
        case .catppuccinMocha:
            ThemePalette(
                appBackground: NSColor(hex: 0x11111B),
                windowBackground: NSColor(hex: 0x181825),
                editorBackground: NSColor(hex: 0x1E1E2E),
                tabBarBackground: NSColor(hex: 0x313244),
                hoveredTabBackground: NSColor(hex: 0xCBA6F7, alpha: 0.18),
                primaryText: NSColor(hex: 0xCDD6F4),
                sidebarText: NSColor(hex: 0xCDD6F4, alpha: 0.94),
                folderSidebarText: NSColor(hex: 0xBAC2DE),
                sidebarHeaderText: NSColor(hex: 0xBAC2DE, alpha: 0.84),
                inactiveTabText: NSColor(hex: 0xA6ADC8),
                lineNumberText: NSColor(hex: 0x6C7086),
                activeControlTint: NSColor(hex: 0xCDD6F4),
                defaultControlTint: NSColor(hex: 0xBAC2DE),
                hoveredControlTint: NSColor(hex: 0xF5C2E7),
                inactiveControlTint: NSColor(hex: 0x7F849C),
                primaryActionBackground: NSColor(hex: 0xCBA6F7),
                primaryActionText: NSColor(hex: 0x1E1E2E),
                subtleSelectionFill: NSColor(hex: 0x45475A, alpha: 0.86),
                syntaxHeadingMarker: NSColor(hex: 0xF38BA8),
                syntaxHeadingText: NSColor(hex: 0xFAB387),
                syntaxListMarker: NSColor(hex: 0xF9E2AF),
                syntaxBlockquoteMarker: NSColor(hex: 0x89DCEB),
                syntaxInlineCode: NSColor(hex: 0xF5C2E7),
                syntaxCodeFence: NSColor(hex: 0x94E2D5),
                syntaxCodeBlockBackground: NSColor(hex: 0x313244, alpha: 0.56),
                syntaxLinkText: NSColor(hex: 0x89DCEB),
                syntaxLinkURL: NSColor(hex: 0xA6E3A1),
                syntaxEmphasisMarker: NSColor(hex: 0xFAB387),
                syntaxThematicBreak: NSColor(hex: 0x6C7086),
                syntaxComment: NSColor(hex: 0x7F849C),
                syntaxString: NSColor(hex: 0xA6E3A1),
                syntaxVariable: NSColor(hex: 0xB4BEFE),
                syntaxKeyword: NSColor(hex: 0xCBA6F7),
                syntaxOperator: NSColor(hex: 0x74C7EC),
                syntaxBuiltin: NSColor(hex: 0xFAB387),
                syntaxPropertyKey: NSColor(hex: 0x89DCEB)
            )
        }
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
