import AppKit

@MainActor
final class ActiveWorkspaceResolver {
    func activeEditorContentViewController() -> EditorContentViewController? {
        (NSApp.keyWindow?.contentViewController as? EditorContentViewController)
            ?? (NSApp.mainWindow?.contentViewController as? EditorContentViewController)
    }

    func activeWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }
}
