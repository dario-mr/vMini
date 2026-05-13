import AppKit
import UniformTypeIdentifiers

@MainActor
final class Document: NSDocument {
    static let supportedTypes: [UTType] = [.plainText, .text]

    let sessionIdentifier: UUID

    private let contentController: DocumentContentController
    private let editorSession = DocumentEditorSession()
    private let openDocumentsStore: OpenDocumentsStore
    private let fileLifecycleController: DocumentFileLifecycleController
    private var syntaxHighlightingObservers: [UUID: (Document) -> Void] = [:]

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
            Task { @MainActor in
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
        fileLifecycleController.reloadFromDiskAfterExternalChange(
            fileURL: fileURL,
            restartWatcher: restartWatcher,
            readFromData: { [weak self] data, typeName in
                try self?.read(from: data, ofType: typeName)
            },
            updateResolvedFileType: { [weak self] typeName in
                self?.fileType = typeName
            },
            onReload: { [weak self] in
                self?.updateChangeCount(.changeCleared)
                self?.undoManager?.removeAllActions()
            },
            onExternalChangeReload: { [weak self] restartWatcher in
                guard restartWatcher else { return }
                self?.reloadFromDiskAfterExternalChange(restartWatcher: true)
            }
        )
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
                contentController.updateRead(typeName: typeName, text: decoded)
                editorSession.update(text: decoded, syntaxLanguage: syntaxLanguage)
                notifySyntaxHighlightingDidChange()
            }
            return
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
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

    private func notifySyntaxHighlightingDidChange() {
        for observer in syntaxHighlightingObservers.values {
            observer(self)
        }
    }
}
