import AppKit

extension ThemeCatalog {
    static let nordPalette = ThemePalette(
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
        syntaxPalette: SyntaxThemePalette(
            headingMarker: NSColor(hex: 0xBF616A),
            headingText: NSColor(hex: 0xD08770),
            listMarker: NSColor(hex: 0xEBCB8B),
            blockquoteMarker: NSColor(hex: 0x88C0D0),
            inlineCode: NSColor(hex: 0xB48EAD),
            codeFence: NSColor(hex: 0x8FBCBB),
            codeBlockBackground: NSColor(hex: 0x3B4252, alpha: 0.58),
            linkText: NSColor(hex: 0x88C0D0),
            linkURL: NSColor(hex: 0xA3BE8C),
            emphasisMarker: NSColor(hex: 0xD08770),
            thematicBreak: NSColor(hex: 0x4C566A),
            comment: NSColor(hex: 0x616E88),
            string: NSColor(hex: 0xA3BE8C),
            variable: NSColor(hex: 0xB48EAD),
            keyword: NSColor(hex: 0x81A1C1),
            operator: NSColor(hex: 0x81A1C1),
            builtin: NSColor(hex: 0xD08770),
            propertyKey: NSColor(hex: 0x81A1C1)
        )
    )
}
