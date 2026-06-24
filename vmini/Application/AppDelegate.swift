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

        if !SessionRestorer.reopenLastFiles() {
            WorkspaceDocumentCoordinator.shared.createUntitledDocument()
        }

        documentsObservation = OpenDocumentsStore.shared.observe { [weak self] _ in
            self?.handleOpenDocumentsDidChange()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let documentController = NSDocumentController.shared
        guard documentController.hasEditedDocuments else {
            SessionRestorer.prepareForTermination()
            return .terminateNow
        }

        documentController.reviewUnsavedDocuments(
            withAlertTitle: nil,
            cancellable: true,
            delegate: self,
            didReviewAllSelector: #selector(documentController(_:didReviewAll:contextInfo:)),
            contextInfo: nil
        )
        return .terminateLater
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

    @objc(documentController:didReviewAll:contextInfo:)
    private func documentController(
        _ documentController: NSDocumentController,
        didReviewAll: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if didReviewAll {
            SessionRestorer.prepareForTermination()
        } else {
            SessionRestorer.cancelTermination()
        }
        NSApp.reply(toApplicationShouldTerminate: didReviewAll)
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        commandDispatcher.validateMenuItem(menuItem)
    }
}
