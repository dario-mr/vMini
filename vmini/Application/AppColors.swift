import AppKit

@MainActor
enum AppColors {
    static var appBackground: NSColor { ThemeManager.shared.palette.appBackground }
    static var windowBackground: NSColor { ThemeManager.shared.palette.windowBackground }

    static var editorBackground: NSColor { ThemeManager.shared.palette.editorBackground }
    static var tabBarBackground: NSColor { ThemeManager.shared.palette.tabBarBackground }
    static var hoveredTabBackground: NSColor { ThemeManager.shared.palette.hoveredTabBackground }

    static var primaryText: NSColor { ThemeManager.shared.palette.primaryText }
    static var sidebarText: NSColor { ThemeManager.shared.palette.sidebarText }
    static var folderSidebarText: NSColor { ThemeManager.shared.palette.folderSidebarText }
    static var sidebarHeaderText: NSColor { ThemeManager.shared.palette.sidebarHeaderText }
    static var inactiveTabText: NSColor { ThemeManager.shared.palette.inactiveTabText }
    static var lineNumberText: NSColor { ThemeManager.shared.palette.lineNumberText }

    static var activeControlTint: NSColor { ThemeManager.shared.palette.activeControlTint }
    static var defaultControlTint: NSColor { ThemeManager.shared.palette.defaultControlTint }
    static var hoveredControlTint: NSColor { ThemeManager.shared.palette.hoveredControlTint }
    static var inactiveControlTint: NSColor { ThemeManager.shared.palette.inactiveControlTint }
    static var primaryActionBackground: NSColor { ThemeManager.shared.palette.primaryActionBackground }
    static var primaryActionText: NSColor { ThemeManager.shared.palette.primaryActionText }

    static var subtleSelectionFill: NSColor { ThemeManager.shared.palette.subtleSelectionFill }
}
