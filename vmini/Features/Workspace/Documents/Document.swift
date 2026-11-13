import AppKit
import UniformTypeIdentifiers

@MainActor
final class Document: NSDocument {
    nonisolated static let supportedTypes: [UTType] = [.plainText, .text, ParquetPage.contentType]

    let sessionIdentifier: UUID

    private let contentController: DocumentContentController
    private var savedText = "" {
        didSet { savedTextLength = (savedText as NSString).length }
    }
    private var savedTextLength = 0
    private let editorSession = DocumentEditorSession()
    private(set) var parquetSession: ParquetSession?
    private var parquetController: ParquetViewController?
    var isReadOnly: Bool { parquetSession != nil }
    private let openDocumentsStore: OpenDocumentsStore
    private let fileLifecycleController: DocumentFileLifecycleController
    private let syntaxHighlightingObservers = Observers<Document>()
    private var isPresentingExternalChangeAlert = false
    private(set) var contentRevision: UInt64 = 0

    var isPreview: Bool { openDocumentsStore.previewDocument === self }

    func keepOpen() {
        openDocumentsStore.keepOpen(self)
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        guard MainActor.assumeIsolated({ !isReadOnly }) else { return }
        super.updateChangeCount(change)
        MainActor.assumeIsolated {
            if isDocumentEdited {
                keepOpen()
            }
        }
    }

    var restorableReference: RestorableDocumentReference {
        RestorableDocumentReference(fileURL: fileURL, sessionIdentifier: sessionIdentifier)
    }

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

    func observeSyntaxHighlightingChanges(_ observer: @escaping (Document) -> Void) -> ObservationToken {
        syntaxHighlightingObservers.add(observer, initialState: self)
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
                openDocumentsStore.migratePinnedIdentifier(
                    from: oldValue,
                    to: fileURL,
                    sessionIdentifier: sessionIdentifier
                )
                let currentText = contentController.currentText(editorText: editorSession.currentEditorText())
                let currentSyntaxLanguage = syntaxLanguage
                fileLifecycleController.stopWatching()
                contentController.applyFileURLChange(from: oldValue, to: fileURL)
                fileLifecycleController.watch(self)
                editorSession.update(text: currentText, syntaxLanguage: currentSyntaxLanguage)
                notifySyntaxHighlightingDidChange()
                openDocumentsStore.refresh()
                SessionRestorer.refreshTerminationSnapshotIfNeeded()

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
        [UTType.plainText.identifier, UTType.text.identifier]
    }

    override class var autosavesInPlace: Bool {
        false
    }

    override func makeWindowControllers() {
        WorkspaceDocumentCoordinator.shared.present(document: self)
    }

    override func close() {
        fileLifecycleController.handleClose()
        parquetSession?.close()
        parquetController = nil
        editorSession.clear()
        super.close()
        openDocumentsStore.unregister(self)
    }

    override func save(_ sender: Any?) {
        guard !isReadOnly else { return }
        fileLifecycleController.prepareForSave()
        super.save(sender)
        fileLifecycleController.finishSave(self)
    }

    override func saveAs(_ sender: Any?) {
        guard !isReadOnly else { return }
        fileLifecycleController.prepareForSave()
        super.saveAs(sender)
        fileLifecycleController.finishSave(self)
    }

    func presentExternalChangeAlert(fileIsMissing: Bool) {
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
                    fileLifecycleController.reload(self, restartWatcher: false)
                }
                return
            }

            if response == .alertSecondButtonReturn && !fileIsMissing {
                fileLifecycleController.reload(self, restartWatcher: false, reloadEvenIfEdited: true)
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
            try validateWrite(to: url, ofType: typeName)
            try writeCurrentText(to: url, atomically: true)
        }
    }

    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        try MainActor.assumeIsolated { try validateWrite(to: url, ofType: typeName) }
        let fileManager = FileManager.default
        if !fileManager.isWritableFile(atPath: url.deletingLastPathComponent().path) {
            if
                fileManager.fileExists(atPath: url.path),
                fileManager.isWritableFile(atPath: url.path)
            {
                try MainActor.assumeIsolated {
                    try writeCurrentText(to: url, atomically: false)
                }
            } else {
                try MainActor.assumeIsolated {
                    try writeCurrentTextWithAuthorization(to: url)
                }
            }
        } else {
            try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        }
    }

    private func writeCurrentText(to url: URL, atomically: Bool) throws {
        let currentText = contentController.currentText(editorText: editorSession.currentEditorText())
        contentController.updateText(currentText)
        if atomically {
            try currentText.write(to: url, atomically: true, encoding: .utf8)
        } else {
            let file = try FileHandle(forWritingTo: url)
            do {
                try file.truncate(atOffset: 0)
                try file.write(contentsOf: Data(currentText.utf8))
                try file.close()
            } catch {
                try? file.close()
                throw error
            }
        }
        savedText = currentText
        editorSession.markChangesSaved()
    }

    private func writeCurrentTextWithAuthorization(to url: URL) throws {
        let currentText = contentController.currentText(editorText: editorSession.currentEditorText())
        contentController.updateText(currentText)
        try PrivilegedFileWriter.write(Data(currentText.utf8), to: url)
        savedText = currentText
        editorSession.markChangesSaved()
    }

    private func validateWrite(to url: URL, ofType typeName: String) throws {
        guard !isReadOnly, typeName != ParquetPage.typeIdentifier, !ParquetPage.recognizes(url) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                          userInfo: [NSLocalizedDescriptionKey: "Parquet files are read-only."])
        }
    }

    override func read(from url: URL, ofType typeName: String) throws {
        if ParquetPage.recognizes(url) || typeName == ParquetPage.typeIdentifier {
            MainActor.assumeIsolated {
                installLoadedPayload(DocumentPayload(url: url, typeName: ParquetPage.typeIdentifier, content: .parquet))
            }
        } else {
            try super.read(from: url, ofType: typeName)
        }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard typeName != ParquetPage.typeIdentifier else { throw CocoaError(.fileReadUnsupportedScheme) }
        if let decoded = String(data: data, encoding: .utf8) {
            MainActor.assumeIsolated {
                AppPerformanceProfiler.measure("DocumentInstall") {
                    installLoadedContent(decoded)
                }
            }
            return
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func installLoadedContent(_ text: String) {
        parquetSession?.close()
        parquetSession = nil
        parquetController = nil
        hasUndoManager = true
        contentRevision &+= 1
        contentController.updateText(text)
        savedText = text
        editorSession.update(text: text, syntaxLanguage: syntaxLanguage)
        notifySyntaxHighlightingDidChange()
    }

    func installLoadedPayload(_ payload: DocumentPayload) {
        switch payload.content {
        case .text(let text): installLoadedContent(text)
        case .parquet:
            super.updateChangeCount(.changeCleared)
            contentRevision &+= 1
            editorSession.clear()
            if let parquetSession {
                parquetSession.reload(from: payload.url)
            } else {
                parquetSession = ParquetSession(url: payload.url)
            }
            hasUndoManager = false
            notifySyntaxHighlightingDidChange()
        }
    }

    func parquetViewController() -> ParquetViewController? {
        guard let parquetSession else { return nil }
        if let parquetController { return parquetController }
        let controller = ParquetViewController(session: parquetSession)
        parquetController = controller
        return controller
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
            // Perf: a different length proves an edit without walking the whole text on every keystroke.
            let matchesSavedText = (editorViewController.text as NSString).length == savedTextLength
                && editorViewController.text.utf8.elementsEqual(savedText.utf8)
            updateChangeCount(matchesSavedText ? .changeCleared : .changeDone)

            if wasEdited != isDocumentEdited {
                openDocumentsStore.refresh()
            }
            if !isDocumentEdited {
                editorViewController.markChangesSaved()
            }
        }
        editorViewController.syntaxLanguage = syntaxLanguage
        editorViewController.documentURLProvider = { [weak self] in self?.fileURL }
        return editorViewController
    }

    func setSyntaxLanguageOverride(_ language: SyntaxLanguage?) {
        guard !isReadOnly else { return }
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
        syntaxHighlightingObservers.notify(self)
    }
}

extension Document: ExternallyReloadableDocument {
    func installReloadedPayload(_ payload: DocumentPayload) {
        installLoadedPayload(payload)
        fileType = payload.typeName
        updateChangeCount(.changeCleared)
        undoManager?.removeAllActions()
    }
}
