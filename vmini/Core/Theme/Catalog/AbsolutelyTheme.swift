import AppKit

extension ThemeCatalog {
    static let absolutelyPalette = ThemePalette(
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
        syntaxPalette: SyntaxThemePalette(
            headingMarker: NSColor(hex: 0xCC7D5E),
            headingText: NSColor(hex: 0xE8A58B),
            listMarker: NSColor(hex: 0xCC7D5E),
            blockquoteMarker: NSColor(hex: 0xCC7D5E, alpha: 0.85),
            inlineCode: NSColor(hex: 0xF2C6B5),
            codeFence: NSColor(hex: 0xCC7D5E),
            codeBlockBackground: NSColor(hex: 0xF9F9F7, alpha: 0.05),
            linkText: NSColor(hex: 0xCC7D5E),
            linkURL: NSColor(hex: 0x00C853),
            emphasisMarker: NSColor(hex: 0xCC7D5E),
            thematicBreak: NSColor(hex: 0x5C5C58),
            comment: NSColor(hex: 0x8F8F87),
            string: NSColor(hex: 0xDDE68B),
            variable: NSColor(hex: 0xD7B7F6),
            keyword: NSColor(hex: 0xD97757),
            operator: NSColor(hex: 0xF3E7D4),
            builtin: NSColor(hex: 0xF0B36A),
            option: NSColor(hex: 0x00C853),
            propertyKey: NSColor(hex: 0xCC7D5E)
        )
    )
}
