import AppKit

@MainActor
final class AppCommandDispatcher: NSObject, NSMenuItemValidation {
    private let workspaceResolver: ActiveWorkspaceResolver
    private let documentRouter: WorkspaceDocumentRouting
    private let makeGoToLineWindowController: () -> GoToLineWindowController
    private lazy var goToLineWindowController = makeGoToLineWindowController()

    init(
        workspaceResolver: ActiveWorkspaceResolver,
        documentRouter: WorkspaceDocumentRouting,
        makeGoToLineWindowController: @escaping () -> GoToLineWindowController
    ) {
        self.workspaceResolver = workspaceResolver
        self.documentRouter = documentRouter
        self.makeGoToLineWindowController = makeGoToLineWindowController
        super.init()
    }

    override convenience init() {
        self.init(
            workspaceResolver: ActiveWorkspaceResolver(),
            documentRouter: WorkspaceDocumentCoordinator.shared,
            makeGoToLineWindowController: { GoToLineWindowController() }
        )
    }

    @objc func toggleWordWrap(_ sender: Any?) { EditorSettings.toggleWordWrap() }
    @objc func toggleInvisibleCharacters(_ sender: Any?) { EditorSettings.toggleInvisibleCharacters() }
    @objc func newDocument(_ sender: Any?) { documentRouter.createUntitledDocument() }
    @objc func showSettings(_ sender: Any?) { WorkspaceWindowController.shared.presentSettingsSheet() }

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
                OpenURLRouter.open(openPanel.urls, tabbedIn: self.workspaceResolver.activeWindow())
            }
        }
    }

    @objc
    func openRecentDocument(_ sender: Any?) {
        guard let fileURL = (sender as? NSMenuItem)?.representedObject as? URL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        OpenURLRouter.open([fileURL], tabbedIn: workspaceResolver.activeWindow())
    }

    @objc func clearRecentDocuments(_ sender: Any?) { NSDocumentController.shared.clearRecentDocuments(sender) }
    @objc func saveCurrentDocument(_ sender: Any?) { OpenDocumentsStore.shared.activeDocument?.save(sender) }
    @objc func saveCurrentDocumentAs(_ sender: Any?) { OpenDocumentsStore.shared.activeDocument?.saveAs(sender) }
    @objc func closeCurrentDocument(_ sender: Any?) { documentRouter.closeCurrentDocument() }
    @objc func reopenClosedDocument(_ sender: Any?) { documentRouter.reopenMostRecentClosedDocument() }
    @objc func formatJSON(_ sender: Any?) { workspaceResolver.activeEditorContentViewController()?.formatJSON() }

    @objc
    func showGoToLine(_ sender: Any?) {
        guard let editorController = workspaceResolver.activeEditorContentViewController() else { return }
        guard let window = workspaceResolver.activeWindow() else { return }

        goToLineWindowController.present(
            currentLineNumber: editorController.currentLineNumber(),
            asSheetFor: window
        ) { [weak editorController] requestedLine in
            guard let editorController else { return }
            _ = editorController.goToLine(requestedLine)
        }
    }

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

        if menuItem.action == #selector(reopenClosedDocument(_:)) {
            return ClosedDocumentHistory.shared.canReopenClosedDocument
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
