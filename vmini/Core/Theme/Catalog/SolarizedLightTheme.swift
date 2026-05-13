import AppKit

extension ThemeCatalog {
    static let solarizedLightPalette = ThemePalette(
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
        syntaxPalette: SyntaxThemePalette(
            headingMarker: NSColor(hex: 0xDC322F),
            headingText: NSColor(hex: 0xCB4B16),
            listMarker: NSColor(hex: 0xB58900),
            blockquoteMarker: NSColor(hex: 0x2AA198),
            inlineCode: NSColor(hex: 0x6C71C4),
            codeFence: NSColor(hex: 0x2AA198),
            codeBlockBackground: NSColor(hex: 0xEEE8D5, alpha: 0.78),
            linkText: NSColor(hex: 0x268BD2),
            linkURL: NSColor(hex: 0x859900),
            emphasisMarker: NSColor(hex: 0xCB4B16),
            thematicBreak: NSColor(hex: 0x93A1A1),
            comment: NSColor(hex: 0x93A1A1),
            string: NSColor(hex: 0x859900),
            variable: NSColor(hex: 0x6C71C4),
            keyword: NSColor(hex: 0x268BD2),
            operator: NSColor(hex: 0x2AA198),
            builtin: NSColor(hex: 0xCB4B16),
            propertyKey: NSColor(hex: 0xCB4B16)
        )
    )
}
