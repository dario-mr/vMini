import AppKit

@MainActor
final class DocumentFileLifecycleController {
    private let externalChangeCoordinator: DocumentExternalChangeCoordinator
    private let typeResolver: NSDocumentController
    private let openDocumentsStore: OpenDocumentsStore

    init(
        externalChangeCoordinator: DocumentExternalChangeCoordinator,
        typeResolver: NSDocumentController,
        openDocumentsStore: OpenDocumentsStore
    ) {
        self.externalChangeCoordinator = externalChangeCoordinator
        self.typeResolver = typeResolver
        self.openDocumentsStore = openDocumentsStore
    }

    convenience init(openDocumentsStore: OpenDocumentsStore) {
        self.init(
            externalChangeCoordinator: DocumentExternalChangeCoordinator(),
            typeResolver: .shared,
            openDocumentsStore: openDocumentsStore
        )
    }

    func handleFileURLChange(
        from oldValue: URL?,
        to newValue: URL?,
        contentController: DocumentContentController,
        editorSession: DocumentEditorSession,
        currentText: String,
        syntaxLanguage: SyntaxLanguage,
        onExternalChangeReload: @escaping @MainActor (Bool) -> Void,
        onSyntaxHighlightingChanged: () -> Void
    ) {
        contentController.applyFileURLChange(from: oldValue, to: newValue)
        restartWatching(fileURL: newValue, onExternalChangeReload: onExternalChangeReload)
        editorSession.update(text: currentText, syntaxLanguage: syntaxLanguage)
        onSyntaxHighlightingChanged()
        openDocumentsStore.refresh()
    }

    func prepareForSave() {
        externalChangeCoordinator.stop()
    }

    func finishSave(fileURL: URL?, onExternalChangeReload: @escaping @MainActor (Bool) -> Void) {
        restartWatching(fileURL: fileURL, onExternalChangeReload: onExternalChangeReload)
        openDocumentsStore.refresh()
    }

    func handleClose() {
        externalChangeCoordinator.stop()
    }

    func reloadFromDiskAfterExternalChange(
        fileURL: URL?,
        restartWatcher: Bool,
        readFromData: (Data, String) throws -> Void,
        updateResolvedFileType: (String) -> Void,
        onReload: () -> Void,
        onMissingFile: () -> Void,
        onExternalChangeReload: @escaping @MainActor (Bool) -> Void
    ) {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            onMissingFile()
            return
        }

        do {
            let typeName = try typeResolver.typeForContents(of: fileURL)
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            try readFromData(data, typeName)
            updateResolvedFileType(typeName)
            onReload()
            openDocumentsStore.refresh()

            if restartWatcher {
                restartWatching(fileURL: fileURL, onExternalChangeReload: onExternalChangeReload)
            }
        } catch {
            NSLog("Could not reload externally changed file %@: %@", fileURL.path as NSString, error.localizedDescription)
        }
    }

    private func restartWatching(
        fileURL: URL?,
        onExternalChangeReload: @escaping @MainActor (Bool) -> Void
    ) {
        externalChangeCoordinator.watch(fileURL: fileURL, onReload: onExternalChangeReload)
    }
}
