import AppKit

extension ThemeCatalog {
    static let draculaPalette = ThemePalette(
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
        syntaxPalette: SyntaxThemePalette(
            headingMarker: NSColor(hex: 0xFF79C6),
            headingText: NSColor(hex: 0xFFB3DA),
            listMarker: NSColor(hex: 0xFFB86C),
            blockquoteMarker: NSColor(hex: 0x8BE9FD),
            inlineCode: NSColor(hex: 0xF1FA8C),
            codeFence: NSColor(hex: 0x8BE9FD),
            codeBlockBackground: NSColor(hex: 0x44475A, alpha: 0.42),
            linkText: NSColor(hex: 0x8BE9FD),
            linkURL: NSColor(hex: 0x50FA7B),
            emphasisMarker: NSColor(hex: 0xFF79C6),
            thematicBreak: NSColor(hex: 0x6272A4),
            comment: NSColor(hex: 0x8B92B2),
            string: NSColor(hex: 0xF1FA8C),
            variable: NSColor(hex: 0xBD93F9),
            keyword: NSColor(hex: 0xFF79C6),
            operator: NSColor(hex: 0xFF79C6),
            builtin: NSColor(hex: 0xFFB86C),
            option: NSColor(hex: 0x50FA7B),
            propertyKey: NSColor(hex: 0x8BE9FD)
        )
    )
}
