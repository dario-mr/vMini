import AppKit

extension ThemeCatalog {
    static let gruvboxDarkPalette = ThemePalette(
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
        syntaxPalette: SyntaxThemePalette(
            headingMarker: NSColor(hex: 0xFB4934),
            headingText: NSColor(hex: 0xFABD2F),
            listMarker: NSColor(hex: 0xFABD2F),
            blockquoteMarker: NSColor(hex: 0x83A598),
            inlineCode: NSColor(hex: 0xD3869B),
            codeFence: NSColor(hex: 0x8EC07C),
            codeBlockBackground: NSColor(hex: 0x3C3836, alpha: 0.48),
            linkText: NSColor(hex: 0x83A598),
            linkURL: NSColor(hex: 0x8EC07C),
            emphasisMarker: NSColor(hex: 0xFE8019),
            thematicBreak: NSColor(hex: 0x665C54),
            comment: NSColor(hex: 0x928374),
            string: NSColor(hex: 0xB8BB26),
            variable: NSColor(hex: 0xD3869B),
            keyword: NSColor(hex: 0xFB4934),
            operator: NSColor(hex: 0x83A598),
            builtin: NSColor(hex: 0xFE8019),
            option: NSColor(hex: 0x8EC07C),
            propertyKey: NSColor(hex: 0x83A598)
        )
    )
}
