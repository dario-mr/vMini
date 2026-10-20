import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let commandDispatcher = AppCommandDispatcher()
    private var documentsObservation: ObservationToken?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        _ = ThemeManager.shared
        MenuBuilder.installMainMenu(commandTarget: commandDispatcher)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = WorkspaceWindowController.shared

        documentsObservation = OpenDocumentsStore.shared.observe { [weak self] _ in
            self?.handleOpenDocumentsDidChange()
        }

        Task { @MainActor in
            if await SessionRestorer.reopenLastFiles() == false {
                WorkspaceDocumentCoordinator.shared.createUntitledDocument()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SessionRestorer.prepareForTermination()
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }

        if let activeDocument = OpenDocumentsStore.shared.activeDocument {
            WorkspaceDocumentCoordinator.shared.present(document: activeDocument)
        } else if let firstDocument = OpenDocumentsStore.shared.documents.first {
            WorkspaceDocumentCoordinator.shared.present(document: firstDocument)
        } else {
            WorkspaceDocumentCoordinator.shared.createUntitledDocument()
        }

        return true
    }

    @objc
    func performQuit(_ sender: Any?) {
        SessionRestorer.prepareForTermination()
        NSApp.terminate(sender)
    }

    private func handleOpenDocumentsDidChange() {
        SessionRestorer.scheduleSaveOpenFiles()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        commandDispatcher.validateMenuItem(menuItem)
    }
}
