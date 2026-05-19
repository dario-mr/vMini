import AppKit

extension ThemeCatalog {
    static let defaultPalette = ThemePalette(
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
