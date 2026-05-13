import AppKit

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
    let syntaxPalette: SyntaxThemePalette

    var syntaxTheme: SyntaxTheme {
        syntaxPalette.makeSyntaxTheme(plainText: primaryText)
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
