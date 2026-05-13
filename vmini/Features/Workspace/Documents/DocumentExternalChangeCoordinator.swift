import AppKit

@MainActor
final class DocumentExternalChangeCoordinator {
    private let watcher = DocumentFileWatcher()

    func watch(fileURL: URL?, onReload: @escaping @MainActor (Bool) -> Void) {
        watcher.watch(fileURL: fileURL, onChange: onReload)
    }

    func stop() {
        watcher.stop()
    }
}
