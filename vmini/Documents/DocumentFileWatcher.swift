import Darwin
import Foundation

@MainActor
final class DocumentFileWatcher {
    typealias ChangeHandler = @MainActor (_ restartWatcher: Bool) -> Void

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var pendingReload: Task<Void, Never>?
    private var onChange: ChangeHandler?

    func watch(fileURL: URL?, onChange: @escaping ChangeHandler) {
        stop()
        self.onChange = onChange

        guard let fileURL else { return }

        let fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        watcher.setEventHandler { [weak self, weak watcher] in
            Task { @MainActor in
                guard let self, let watcher else { return }

                let event = watcher.data
                let shouldRestartWatcher = event.contains(.delete) || event.contains(.rename)
                self.scheduleReload(restartWatcher: shouldRestartWatcher)
            }
        }
        watcher.setCancelHandler { [fileDescriptor] in
            Darwin.close(fileDescriptor)
        }

        fileWatcher = watcher
        watcher.resume()
    }

    func stop() {
        pendingReload?.cancel()
        pendingReload = nil
        fileWatcher?.cancel()
        fileWatcher = nil
        onChange = nil
    }

    private func scheduleReload(restartWatcher: Bool) {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.onChange?(restartWatcher)
        }
    }
}
