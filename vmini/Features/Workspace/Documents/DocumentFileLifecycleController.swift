import AppKit

@MainActor
final class DocumentFileLifecycleController {
    typealias PayloadLoader = (URL) async throws -> DocumentPayload

    private let externalChangeCoordinator: DocumentExternalChangeCoordinator
    private let openDocumentsStore: OpenDocumentsStore
    private let payloadLoader: PayloadLoader
    private var reloadGeneration: UInt64 = 0
    private var reloadNeedsWatcherRestart = false

    init(
        externalChangeCoordinator: DocumentExternalChangeCoordinator,
        openDocumentsStore: OpenDocumentsStore,
        payloadLoader: @escaping PayloadLoader = DocumentPayloadLoader.load(from:)
    ) {
        self.externalChangeCoordinator = externalChangeCoordinator
        self.openDocumentsStore = openDocumentsStore
        self.payloadLoader = payloadLoader
    }

    convenience init(openDocumentsStore: OpenDocumentsStore) {
        self.init(
            externalChangeCoordinator: DocumentExternalChangeCoordinator(),
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
        stopWatching()
        contentController.applyFileURLChange(from: oldValue, to: newValue)
        restartWatching(fileURL: newValue, onExternalChangeReload: onExternalChangeReload)
        editorSession.update(text: currentText, syntaxLanguage: syntaxLanguage)
        onSyntaxHighlightingChanged()
        openDocumentsStore.refresh()
        SessionRestorer.refreshTerminationSnapshotIfNeeded()
    }

    func prepareForSave() {
        stopWatching()
    }

    func finishSave(fileURL: URL?, onExternalChangeReload: @escaping @MainActor (Bool) -> Void) {
        restartWatching(fileURL: fileURL, onExternalChangeReload: onExternalChangeReload)
        openDocumentsStore.refresh()
    }

    func handleClose() {
        stopWatching()
    }

    func stopWatching() {
        reloadGeneration &+= 1
        reloadNeedsWatcherRestart = false
        externalChangeCoordinator.stop()
    }

    func reloadFromDiskAfterExternalChange(
        fileURL: URL?,
        currentFileURL: () -> URL?,
        contentRevision: () -> UInt64,
        startingRevision: UInt64,
        restartWatcher: Bool,
        isDocumentEdited: Bool,
        isDocumentCurrentlyEdited: () -> Bool,
        reloadEvenIfEdited: Bool,
        installPayload: (DocumentPayload) -> Void,
        onReload: () -> Void,
        onMissingFile: () -> Void,
        onMissingFileWithUnsavedChanges: () -> Void,
        onExternalChangeWithUnsavedChanges: (Bool) -> Void,
        onExternalChangeReload: @escaping @MainActor (Bool) -> Void
    ) async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        reloadNeedsWatcherRestart = reloadNeedsWatcherRestart || restartWatcher
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            stopWatching()
            if isDocumentEdited {
                onMissingFileWithUnsavedChanges()
            } else {
                onMissingFile()
            }
            return
        }

        if isDocumentEdited && !reloadEvenIfEdited {
            onExternalChangeWithUnsavedChanges(reloadNeedsWatcherRestart)
            if reloadNeedsWatcherRestart {
                restartWatching(fileURL: fileURL, onExternalChangeReload: onExternalChangeReload)
            }
            return
        }

        let standardizedURL = fileURL.standardizedFileURL
        do {
            let payload = try await payloadLoader(standardizedURL)
            guard generation == reloadGeneration else { return }
            guard currentFileURL()?.standardizedFileURL == standardizedURL else { return }
            guard contentRevision() == startingRevision else {
                if isDocumentCurrentlyEdited() {
                    onExternalChangeWithUnsavedChanges(false)
                }
                if reloadNeedsWatcherRestart {
                    restartWatching(fileURL: currentFileURL(), onExternalChangeReload: onExternalChangeReload)
                }
                return
            }

            installPayload(payload)
            onReload()
            openDocumentsStore.refresh()

            if reloadNeedsWatcherRestart {
                restartWatching(fileURL: currentFileURL(), onExternalChangeReload: onExternalChangeReload)
            }
        } catch {
            guard generation == reloadGeneration else { return }
            NSLog("Could not reload externally changed file %@: %@", fileURL.path as NSString, error.localizedDescription)
            if reloadNeedsWatcherRestart, currentFileURL()?.standardizedFileURL == standardizedURL {
                restartWatching(fileURL: currentFileURL(), onExternalChangeReload: onExternalChangeReload)
            }
        }
    }

    private func restartWatching(
        fileURL: URL?,
        onExternalChangeReload: @escaping @MainActor (Bool) -> Void
    ) {
        reloadNeedsWatcherRestart = false
        externalChangeCoordinator.watch(fileURL: fileURL, onReload: onExternalChangeReload)
    }
}
