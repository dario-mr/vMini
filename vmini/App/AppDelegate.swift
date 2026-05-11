import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var goToLineWindowController = GoToLineWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        _ = ThemeManager.shared
        MenuBuilder.installMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenDocumentsDidChange),
            name: OpenDocumentsStore.didChangeNotification,
            object: nil
        )

        if !SessionRestorer.reopenLastFiles() {
            WorkspaceWindowController.shared.createUntitledDocument()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MenuBuilder.installMainMenu()
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
            WorkspaceWindowController.shared.present(document: activeDocument)
        } else if let firstDocument = OpenDocumentsStore.shared.documents.first {
            WorkspaceWindowController.shared.present(document: firstDocument)
        } else {
            WorkspaceWindowController.shared.createUntitledDocument()
        }

        return true
    }

    @objc
    func toggleWordWrap(_ sender: Any?) {
        EditorSettings.toggleWordWrap()
    }

    @objc
    func toggleInvisibleCharacters(_ sender: Any?) {
        EditorSettings.toggleInvisibleCharacters()
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
    func openRecentDocument(_ sender: Any?) {
        guard let fileURL = (sender as? NSMenuItem)?.representedObject as? URL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        OpenURLRouter.open([fileURL], tabbedIn: NSApp.keyWindow ?? NSApp.mainWindow)
    }

    @objc
    func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
        MenuBuilder.installMainMenu()
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

    @objc
    func formatJSON(_ sender: Any?) {
        let editorController = (NSApp.keyWindow?.contentViewController as? EditorContentViewController)
            ?? (NSApp.mainWindow?.contentViewController as? EditorContentViewController)
        editorController?.formatJSON()
    }

    @objc
    func showGoToLine(_ sender: Any?) {
        guard let editorController = activeEditorContentViewController() else { return }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        goToLineWindowController.present(
            currentLineNumber: editorController.currentLineNumber(),
            asSheetFor: window
        ) { [weak editorController] requestedLine in
            guard let editorController else { return }
            _ = editorController.goToLine(requestedLine)
        }
    }

    @objc
    func performQuit(_ sender: Any?) {
        SessionRestorer.prepareForTermination()
        NSApp.terminate(sender)
    }

    @objc
    private func handleOpenDocumentsDidChange() {
        SessionRestorer.saveOpenFiles()
        MenuBuilder.installMainMenu()
    }

    private func activeEditorContentViewController() -> EditorContentViewController? {
        (NSApp.keyWindow?.contentViewController as? EditorContentViewController)
            ?? (NSApp.mainWindow?.contentViewController as? EditorContentViewController)
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
        if menuItem.action == #selector(toggleWordWrap(_:)) {
            menuItem.state = EditorSettings.isWordWrapEnabled() ? .on : .off
            return true
        }

        if menuItem.action == #selector(toggleInvisibleCharacters(_:)) {
            menuItem.state = EditorSettings.showsInvisibleCharacters() ? .on : .off
            return true
        }

        if menuItem.action == #selector(showSettings(_:)) {
            return true
        }

        if menuItem.action == #selector(openRecentDocument(_:)) {
            guard let fileURL = menuItem.representedObject as? URL else { return false }
            return FileManager.default.fileExists(atPath: fileURL.path)
        }

        if menuItem.action == #selector(showGoToLine(_:)) {
            return OpenDocumentsStore.shared.activeDocument != nil
        }

        if menuItem.action == #selector(saveCurrentDocument(_:))
            || menuItem.action == #selector(saveCurrentDocumentAs(_:))
            || menuItem.action == #selector(closeCurrentDocument(_:))
            || menuItem.action == #selector(formatJSON(_:)) {
            return OpenDocumentsStore.shared.activeDocument != nil
        }

        return true
    }
}
