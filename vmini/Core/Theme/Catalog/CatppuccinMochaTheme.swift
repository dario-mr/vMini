import AppKit

extension ThemeCatalog {
    static let catppuccinMochaPalette = ThemePalette(
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
        syntaxPalette: SyntaxThemePalette(
            headingMarker: NSColor(hex: 0xF38BA8),
            headingText: NSColor(hex: 0xFAB387),
            listMarker: NSColor(hex: 0xF9E2AF),
            blockquoteMarker: NSColor(hex: 0x89DCEB),
            inlineCode: NSColor(hex: 0xF5C2E7),
            codeFence: NSColor(hex: 0x94E2D5),
            codeBlockBackground: NSColor(hex: 0x313244, alpha: 0.56),
            linkText: NSColor(hex: 0x89DCEB),
            linkURL: NSColor(hex: 0xA6E3A1),
            emphasisMarker: NSColor(hex: 0xFAB387),
            thematicBreak: NSColor(hex: 0x6C7086),
            comment: NSColor(hex: 0x7F849C),
            string: NSColor(hex: 0xA6E3A1),
            variable: NSColor(hex: 0xB4BEFE),
            keyword: NSColor(hex: 0xCBA6F7),
            operator: NSColor(hex: 0x74C7EC),
            builtin: NSColor(hex: 0xFAB387),
            option: NSColor(hex: 0xA6E3A1),
            propertyKey: NSColor(hex: 0x89DCEB)
        )
    )
}
