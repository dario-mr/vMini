import AppKit
import UniformTypeIdentifiers

@MainActor
final class Document: NSDocument {
    nonisolated static let supportedTypes: [UTType] = [.plainText, .text]

    let sessionIdentifier: UUID

    private let contentController: DocumentContentController
    private let editorSession = DocumentEditorSession()
    private let openDocumentsStore: OpenDocumentsStore
    private let fileLifecycleController: DocumentFileLifecycleController
    private var syntaxHighlightingObservers: [UUID: (Document) -> Void] = [:]
    private var isPresentingExternalChangeAlert = false
    private(set) var contentRevision: UInt64 = 0

    var sidebarTitle: String {
        fileURL?.lastPathComponent ?? displayName
    }

    var shortDisplayTitle: String {
        isDocumentEdited ? "• \(sidebarTitle)" : sidebarTitle
    }

    var windowTitle: String {
        guard let fileURL else {
            return displayName
        }

        return (fileURL.path as NSString).abbreviatingWithTildeInPath
    }

    var autoDetectedSyntaxLanguage: SyntaxLanguage {
        contentController.autoDetectedSyntaxLanguage(fileURL: fileURL, sampleText: syntaxDetectionContentSample())
    }

    var syntaxLanguage: SyntaxLanguage {
        contentController.syntaxLanguage(fileURL: fileURL, sampleText: syntaxDetectionContentSample())
    }

    var hasSyntaxLanguageOverride: Bool {
        contentController.hasSyntaxLanguageOverride
    }

    var syntaxOverrideMenuTitle: String {
        contentController.syntaxOverrideMenuTitle(fileURL: fileURL, sampleText: syntaxDetectionContentSample())
    }

    func observeSyntaxHighlightingChanges(_ observer: @escaping (Document) -> Void) -> ObservationToken {
        let identifier = UUID()
        syntaxHighlightingObservers[identifier] = observer
        observer(self)
        return ObservationToken { [weak self] in
            self?.syntaxHighlightingObservers.removeValue(forKey: identifier)
        }
    }

    init(
        sessionIdentifier: UUID,
        syntaxOverrideStore: SyntaxOverrideStore,
        openDocumentsStore: OpenDocumentsStore
    ) {
        self.sessionIdentifier = sessionIdentifier
        self.openDocumentsStore = openDocumentsStore
        self.contentController = DocumentContentController(syntaxOverrideStore: syntaxOverrideStore)
        self.fileLifecycleController = DocumentFileLifecycleController(openDocumentsStore: openDocumentsStore)
        super.init()
        hasUndoManager = true
    }

    override init() {
        self.sessionIdentifier = UUID()
        self.openDocumentsStore = .shared
        self.contentController = DocumentContentController(syntaxOverrideStore: .shared)
        self.fileLifecycleController = DocumentFileLifecycleController(openDocumentsStore: .shared)
        super.init()
        hasUndoManager = true
    }

    convenience init(sessionIdentifier: UUID) {
        self.init(sessionIdentifier: sessionIdentifier, syntaxOverrideStore: .shared, openDocumentsStore: .shared)
    }

    convenience init(syntaxOverrideStore: SyntaxOverrideStore) {
        self.init(sessionIdentifier: UUID(), syntaxOverrideStore: syntaxOverrideStore, openDocumentsStore: .shared)
    }

    override var fileURL: URL? {
        didSet {
            MainActor.assumeIsolated {
                fileLifecycleController.handleFileURLChange(
                    from: oldValue,
                    to: fileURL,
                    contentController: contentController,
                    editorSession: editorSession,
                    currentText: contentController.currentText(editorText: editorSession.currentEditorText()),
                    syntaxLanguage: syntaxLanguage,
                    onExternalChangeReload: { [weak self] restartWatcher in
                        self?.reloadFromDiskAfterExternalChange(restartWatcher: restartWatcher)
                    },
                    onSyntaxHighlightingChanged: { [weak self] in
                        self?.notifySyntaxHighlightingDidChange()
                    }
                )

                if Self.didMoveToTrash(from: oldValue, to: fileURL) {
                    if isDocumentEdited {
                        fileLifecycleController.stopWatching()
                        presentExternalChangeAlert(fileIsMissing: true)
                    } else {
                        close()
                    }
                }
            }
        }
    }

    override class var readableTypes: [String] {
        supportedTypes.map(\.identifier)
    }

    override class var writableTypes: [String] {
        supportedTypes.map(\.identifier)
    }

    override class var autosavesInPlace: Bool {
        false
    }

    override func makeWindowControllers() {
        WorkspaceDocumentCoordinator.shared.present(document: self)
    }

    override func close() {
        fileLifecycleController.handleClose()
        editorSession.clear()
        super.close()
        openDocumentsStore.unregister(self)
    }

    override func save(_ sender: Any?) {
        fileLifecycleController.prepareForSave()
        super.save(sender)
        fileLifecycleController.finishSave(fileURL: fileURL) { [weak self] restartWatcher in
            self?.reloadFromDiskAfterExternalChange(restartWatcher: restartWatcher)
        }
    }

    override func saveAs(_ sender: Any?) {
        fileLifecycleController.prepareForSave()
        super.saveAs(sender)
        fileLifecycleController.finishSave(fileURL: fileURL) { [weak self] restartWatcher in
            self?.reloadFromDiskAfterExternalChange(restartWatcher: restartWatcher)
        }
    }

    private func reloadFromDiskAfterExternalChange(restartWatcher: Bool) {
        reloadFromDiskAfterExternalChange(restartWatcher: restartWatcher, reloadEvenIfEdited: false)
    }

    private func reloadFromDiskAfterExternalChange(restartWatcher: Bool, reloadEvenIfEdited: Bool) {
        let requestedFileURL = fileURL
        let startingRevision = contentRevision
        let wasEdited = isDocumentEdited

        Task { @MainActor [weak self] in
            guard let self else { return }
            await fileLifecycleController.reloadFromDiskAfterExternalChange(
                fileURL: requestedFileURL,
                currentFileURL: { self.fileURL },
                contentRevision: { self.contentRevision },
                startingRevision: startingRevision,
                restartWatcher: restartWatcher,
                isDocumentEdited: wasEdited,
                isDocumentCurrentlyEdited: { self.isDocumentEdited },
                reloadEvenIfEdited: reloadEvenIfEdited,
                installPayload: {
                    self.installLoadedContent($0.text, ofType: $0.typeName)
                    self.fileType = $0.typeName
                },
                onReload: {
                    self.updateChangeCount(.changeCleared)
                    self.undoManager?.removeAllActions()
                },
                onMissingFile: { self.close() },
                onMissingFileWithUnsavedChanges: { self.presentExternalChangeAlert(fileIsMissing: true) },
                onExternalChangeWithUnsavedChanges: { _ in self.presentExternalChangeAlert(fileIsMissing: false) },
                onExternalChangeReload: { [weak self] restartWatcher in
                    guard restartWatcher else { return }
                    self?.reloadFromDiskAfterExternalChange(restartWatcher: true)
                }
            )
        }
    }

    private func presentExternalChangeAlert(fileIsMissing: Bool) {
        guard !isPresentingExternalChangeAlert else { return }
        isPresentingExternalChangeAlert = true

        let alert = NSAlert()
        if fileIsMissing {
            alert.messageText = "The file was deleted or moved to the Trash."
            alert.informativeText = "Your unsaved changes are still open. Save them to a new location?"
            alert.addButton(withTitle: "Save As…")
            alert.addButton(withTitle: "Keep Open")
        } else {
            alert.messageText = "This file changed on disk."
            alert.informativeText = "Keep your unsaved changes or reload the file from disk? Reloading replaces your local edits."
            alert.addButton(withTitle: "Keep My Changes")
            alert.addButton(withTitle: "Reload from Disk")
        }

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            isPresentingExternalChangeAlert = false
            if response == .alertFirstButtonReturn {
                if fileIsMissing {
                    saveAs(nil)
                } else if let fileURL, !FileManager.default.fileExists(atPath: fileURL.path) {
                    reloadFromDiskAfterExternalChange(restartWatcher: false)
                }
                return
            }

            if response == .alertSecondButtonReturn && !fileIsMissing {
                reloadFromDiskAfterExternalChange(restartWatcher: false, reloadEvenIfEdited: true)
            }
        }

        if let window = WorkspaceWindowController.shared.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    override func write(to url: URL, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            let currentText = contentController.currentText(editorText: editorSession.currentEditorText())
            contentController.updateText(currentText)
            return currentText
        }.write(to: url, atomically: true, encoding: .utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        if let decoded = String(data: data, encoding: .utf8) {
            MainActor.assumeIsolated {
                AppPerformanceProfiler.measure("DocumentInstall") {
                    installLoadedContent(decoded, ofType: typeName)
                }
            }
            return
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func installLoadedContent(_ text: String, ofType typeName: String) {
        contentRevision &+= 1
        contentController.updateRead(typeName: typeName, text: text)
        editorSession.update(text: text, syntaxLanguage: syntaxLanguage)
        notifySyntaxHighlightingDidChange()
    }

    func editorViewController(onFileSystemURLsDropped: @escaping ([URL]) -> Void) -> EditorViewController {
        let editorViewController = editorSession.resolveEditorViewController(
            text: contentController.currentText(editorText: editorSession.currentEditorText()),
            syntaxLanguage: syntaxLanguage,
            onFileSystemURLsDropped: onFileSystemURLsDropped
        ) { [weak self] editorViewController in
            guard let self else { return }
            let resolvedSyntaxLanguage = syntaxLanguage
            if editorViewController.syntaxLanguage != resolvedSyntaxLanguage {
                editorViewController.syntaxLanguage = resolvedSyntaxLanguage
                notifySyntaxHighlightingDidChange()
            }
            contentRevision &+= 1
            contentController.updateText(editorViewController.text)
            let wasEdited = isDocumentEdited
            updateChangeCount(.changeDone)

            if wasEdited != isDocumentEdited {
                openDocumentsStore.refresh()
            }
        }
        editorViewController.syntaxLanguage = syntaxLanguage
        return editorViewController
    }

    func setSyntaxLanguageOverride(_ language: SyntaxLanguage?) {
        contentController.setSyntaxLanguageOverride(language, persistenceIdentifier: persistenceIdentifier)
        editorSession.update(
            text: contentController.currentText(editorText: editorSession.currentEditorText()),
            syntaxLanguage: syntaxLanguage
        )
        notifySyntaxHighlightingDidChange()
    }

    private func syntaxDetectionContentSample() -> String {
        let sourceText = contentController.currentText(editorText: editorSession.currentEditorText())
        return String(sourceText.prefix(512))
    }

    private var persistenceIdentifier: String? {
        guard let fileURL else {
            return nil
        }

        return Self.persistenceIdentifier(for: fileURL)
    }

    private static func persistenceIdentifier(for fileURL: URL) -> String {
        fileURL.standardizedFileURL.path
    }

    private static func didMoveToTrash(from oldURL: URL?, to newURL: URL?) -> Bool {
        guard let oldURL, let newURL else { return false }
        return !isTrashURL(oldURL) && isTrashURL(newURL)
    }

    private static func isTrashURL(_ url: URL) -> Bool {
        let trashComponentNames = Set([".Trash", "Trash"])
        return !trashComponentNames.isDisjoint(with: url.standardizedFileURL.pathComponents)
    }

    private func notifySyntaxHighlightingDidChange() {
        for observer in syntaxHighlightingObservers.values {
            observer(self)
        }
    }
}
