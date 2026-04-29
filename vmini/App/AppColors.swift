import AppKit

enum AppColors {
    static let appBackground = NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.13, alpha: 1.0)
    static let windowBackground = NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.17, alpha: 1.0)

    static let editorBackground = NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.20, alpha: 1.0)
    static let tabBarBackground = NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.28, alpha: 1.0)
    static let hoveredTabBackground = editorBackground.withAlphaComponent(0.55)

    static let primaryText = NSColor(white: 0.98, alpha: 1.0)
    static let sidebarText = NSColor(white: 0.88, alpha: 1.0)
    static let folderSidebarText = NSColor(white: 0.86, alpha: 1.0)
    static let sidebarHeaderText = NSColor(white: 0.84, alpha: 1.0)
    static let inactiveTabText = NSColor(white: 0.77, alpha: 1.0)
    static let lineNumberText = NSColor(white: 0.62, alpha: 1.0)

    static let activeControlTint = NSColor(white: 0.80, alpha: 1.0)
    static let defaultControlTint = NSColor(white: 0.70, alpha: 1.0)
    static let hoveredControlTint = NSColor(white: 0.74, alpha: 1.0)
    static let inactiveControlTint = NSColor(white: 0.62, alpha: 1.0)

    static let subtleSelectionFill = NSColor(white: 1.0, alpha: 0.09)
}
