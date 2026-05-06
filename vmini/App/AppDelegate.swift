import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        _ = ThemeManager.shared
        MenuBuilder.installMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !SessionRestorer.reopenLastFiles() {
            WorkspaceWindowController.shared.createUntitledDocument()
        }
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
        false
    }

    @objc
    func toggleWordWrap(_ sender: Any?) {
        EditorSettings.toggleWordWrap()
    }

    @objc
    func newDocument(_ sender: Any?) {
        WorkspaceWindowController.shared.createUntitledDocument()
    }

    @objc
    func showSettings(_ sender: Any?) {
        WorkspaceWindowController.shared.presentSettingsSheet()
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

    @objc
    func saveCurrentDocument(_ sender: Any?) {
        OpenDocumentsStore.shared.activeDocument?.save(sender)
    }

    @objc
    func saveCurrentDocumentAs(_ sender: Any?) {
        OpenDocumentsStore.shared.activeDocument?.saveAs(sender)
    }

    @objc
    func closeCurrentDocument(_ sender: Any?) {
        WorkspaceWindowController.shared.closeCurrentDocument()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleWordWrap(_:)) {
            menuItem.state = EditorSettings.isWordWrapEnabled() ? .on : .off
            return true
        }

        if menuItem.action == #selector(showSettings(_:)) {
            return true
        }

        if menuItem.action == #selector(saveCurrentDocument(_:))
            || menuItem.action == #selector(saveCurrentDocumentAs(_:))
            || menuItem.action == #selector(closeCurrentDocument(_:)) {
            return OpenDocumentsStore.shared.activeDocument != nil
        }

        return true
    }
}
