import AppKit

extension ThemeCatalog {
    static let defaultPalette = ThemePalette(
        appBackground: NSColor(hex: 0x111925),
        windowBackground: NSColor(hex: 0x192432),
        editorBackground: NSColor(hex: 0x1B2837),
        tabBarBackground: NSColor(hex: 0x2C3C51),
        hoveredTabBackground: NSColor(hex: 0x1B2837, alpha: 0.55),
        primaryText: NSColor(hex: 0xDCE5F0),
        sidebarText: NSColor(hex: 0xDCE5F0),
        folderSidebarText: NSColor(hex: 0xCBD6E4),
        sidebarHeaderText: NSColor(hex: 0xC2CEDD),
        inactiveTabText: NSColor(hex: 0x9FB2CA),
        lineNumberText: NSColor(hex: 0x8297B0),
        activeControlTint: NSColor(hex: 0x94BAE8),
        defaultControlTint: NSColor(hex: 0x9FB2CA),
        hoveredControlTint: NSColor(hex: 0xB4C4D8),
        inactiveControlTint: NSColor(hex: 0x8297B0),
        primaryActionBackground: NSColor(hex: 0x4F7DB0),
        primaryActionText: NSColor(hex: 0xFAFAFA),
        subtleSelectionFill: NSColor(hex: 0xFFFFFF, alpha: 0.09),
        syntaxPalette: SyntaxThemePalette(
            headingMarker: NSColor(hex: 0xF55E69),
            headingText: NSColor(hex: 0xFAB0B8),
            listMarker: NSColor(hex: 0xFAB04F),
            blockquoteMarker: NSColor(hex: 0x78C7E0),
            inlineCode: NSColor(hex: 0xC78FDB),
            codeFence: NSColor(hex: 0x6BC9D6),
            codeBlockBackground: NSColor(hex: 0xFFFFFF, alpha: 0.08),
            linkText: NSColor(hex: 0x73B5F5),
            linkURL: NSColor(hex: 0x87E3AB),
            emphasisMarker: NSColor(hex: 0xF7A34D),
            thematicBreak: NSColor(hex: 0xBAC4CC),
            comment: NSColor(hex: 0x75949E),
            string: NSColor(hex: 0x8FD6AB),
            variable: NSColor(hex: 0xC4B0F2),
            keyword: NSColor(hex: 0xF55E69),
            operator: NSColor(hex: 0x91D4EB),
            builtin: NSColor(hex: 0xFAB04F),
            option: NSColor(hex: 0x73B5F5),
            propertyKey: NSColor(hex: 0xFAB04F)
        )
    )
}
