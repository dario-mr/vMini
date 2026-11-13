import AppKit

@MainActor
protocol ExternallyReloadableDocument: AnyObject {
    var fileURL: URL? { get }
    var contentRevision: UInt64 { get }
    var isDocumentEdited: Bool { get }

    func installReloadedPayload(_ payload: DocumentPayload)
    func presentExternalChangeAlert(fileIsMissing: Bool)
    func close()
}

@MainActor
final class DocumentFileLifecycleController {
    typealias PayloadLoader = (URL) async throws -> DocumentPayload

    private let watcher = DocumentFileWatcher()
    private let openDocumentsStore: OpenDocumentsStore
    private let payloadLoader: PayloadLoader
    private var reloadGeneration: UInt64 = 0
    private var reloadNeedsWatcherRestart = false

    init(
        openDocumentsStore: OpenDocumentsStore,
        payloadLoader: @escaping PayloadLoader = DocumentPayloadLoader.load(from:)
    ) {
        self.openDocumentsStore = openDocumentsStore
        self.payloadLoader = payloadLoader
    }

    func watch(_ document: ExternallyReloadableDocument) {
        restartWatching(document, fileURL: document.fileURL)
    }

    func prepareForSave() {
        stopWatching()
    }

    func finishSave(_ document: ExternallyReloadableDocument) {
        watch(document)
        openDocumentsStore.refresh()
    }

    func handleClose() {
        stopWatching()
    }

    func stopWatching() {
        reloadGeneration &+= 1
        reloadNeedsWatcherRestart = false
        watcher.stop()
    }

    @discardableResult
    func reload(
        _ document: ExternallyReloadableDocument,
        restartWatcher: Bool,
        reloadEvenIfEdited: Bool = false
    ) -> Task<Void, Never> {
        let fileURL = document.fileURL
        let startingRevision = document.contentRevision
        let wasEdited = document.isDocumentEdited

        return Task { [weak document] in
            guard let document else { return }
            await self.reload(
                document,
                fileURL: fileURL,
                startingRevision: startingRevision,
                wasEdited: wasEdited,
                restartWatcher: restartWatcher,
                reloadEvenIfEdited: reloadEvenIfEdited
            )
        }
    }

    private func reload(
        _ document: ExternallyReloadableDocument,
        fileURL: URL?,
        startingRevision: UInt64,
        wasEdited: Bool,
        restartWatcher: Bool,
        reloadEvenIfEdited: Bool
    ) async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        reloadNeedsWatcherRestart = reloadNeedsWatcherRestart || restartWatcher
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            stopWatching()
            if wasEdited {
                document.presentExternalChangeAlert(fileIsMissing: true)
            } else {
                document.close()
            }
            return
        }

        if wasEdited && !reloadEvenIfEdited {
            document.presentExternalChangeAlert(fileIsMissing: false)
            if reloadNeedsWatcherRestart {
                restartWatching(document, fileURL: fileURL)
            }
            return
        }

        let standardizedURL = fileURL.standardizedFileURL
        do {
            let payload = try await payloadLoader(standardizedURL)
            guard generation == reloadGeneration else { return }
            guard document.fileURL?.standardizedFileURL == standardizedURL else { return }
            guard document.contentRevision == startingRevision else {
                if document.isDocumentEdited {
                    document.presentExternalChangeAlert(fileIsMissing: false)
                }
                if reloadNeedsWatcherRestart {
                    restartWatching(document, fileURL: document.fileURL)
                }
                return
            }

            document.installReloadedPayload(payload)
            openDocumentsStore.refresh()

            if reloadNeedsWatcherRestart {
                restartWatching(document, fileURL: document.fileURL)
            }
        } catch {
            guard generation == reloadGeneration else { return }
            NSLog("Could not reload externally changed file %@: %@", fileURL.path as NSString, error.localizedDescription)
            if reloadNeedsWatcherRestart, document.fileURL?.standardizedFileURL == standardizedURL {
                restartWatching(document, fileURL: document.fileURL)
            }
        }
    }

    private func restartWatching(_ document: ExternallyReloadableDocument, fileURL: URL?) {
        reloadNeedsWatcherRestart = false
        watcher.watch(fileURL: fileURL) { [weak self, weak document] restartWatcher in
            guard let self, let document else { return }
            self.reload(document, restartWatcher: restartWatcher)
        }
    }
}
