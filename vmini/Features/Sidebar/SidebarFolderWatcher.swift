import Darwin
import Foundation

final class SidebarFolderWatcher {
    private var watchersByPath: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingRefresh: DispatchWorkItem?
    private var onChange: (() -> Void)?

    deinit {
        stop()
    }

    func watch(directoryURLs: [URL], onChange: @escaping () -> Void) {
        self.onChange = onChange

        var uniqueURLs: [String: URL] = [:]
        for url in directoryURLs {
            let standardizedURL = url.standardizedFileURL
            uniqueURLs[standardizedURL.path] = standardizedURL
        }

        for path in watchersByPath.keys where uniqueURLs[path] == nil {
            watchersByPath.removeValue(forKey: path)?.cancel()
        }

        for (path, url) in uniqueURLs where watchersByPath[path] == nil {
            guard let watcher = makeWatcher(for: url) else { continue }
            watchersByPath[path] = watcher
            watcher.resume()
        }
    }

    func stop() {
        pendingRefresh?.cancel()
        pendingRefresh = nil

        for watcher in watchersByPath.values {
            watcher.cancel()
        }
        watchersByPath.removeAll()
        onChange = nil
    }

    private func makeWatcher(for directoryURL: URL) -> DispatchSourceFileSystemObject? {
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        watcher.setEventHandler { [weak self] in
            self?.scheduleRefresh()
        }
        watcher.setCancelHandler { [fileDescriptor] in
            Darwin.close(fileDescriptor)
        }
        return watcher
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        pendingRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: workItem)
    }
}
