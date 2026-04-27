import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        MenuBuilder.installMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SessionRestorer.reopenLastFiles()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MenuBuilder.installMainMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionRestorer.saveOpenFiles()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    @objc
    func toggleWordWrap(_ sender: Any?) {
        EditorSettings.toggleWordWrap()
    }

    @objc
    func openDocumentOrFolder(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.showsHiddenFiles = true
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true

        openPanel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                OpenURLRouter.open(openPanel.urls, tabbedIn: NSApp.keyWindow ?? NSApp.mainWindow)
            }
        }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleWordWrap(_:)) {
            menuItem.state = EditorSettings.isWordWrapEnabled() ? .on : .off
            return true
        }

        return true
    }
}
