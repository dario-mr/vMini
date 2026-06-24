import Darwin
import Foundation

final class SidebarFolderWatcher: @unchecked Sendable {
    private let eventQueue = DispatchQueue(label: "vmini.sidebar-folder-watcher", qos: .utility)
    private var watchersByPath: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingRefresh: DispatchWorkItem?
    private var pendingChangedDirectoryPaths: Set<String> = []
    private var onChange: (([URL]) -> Void)?

    deinit {
        stop()
    }

    func watch(directoryURLs: [URL], onChange: @escaping ([URL]) -> Void) {
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
        pendingChangedDirectoryPaths.removeAll()

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
            queue: eventQueue
        )
        watcher.setEventHandler { [weak self] in
            self?.scheduleRefresh(for: directoryURL)
        }
        watcher.setCancelHandler { [fileDescriptor] in
            Darwin.close(fileDescriptor)
        }
        return watcher
    }

    private func scheduleRefresh(for directoryURL: URL) {
        pendingChangedDirectoryPaths.insert(directoryURL.standardizedFileURL.path)
        pendingRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changedURLs = self.pendingChangedDirectoryPaths.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            self.pendingChangedDirectoryPaths.removeAll()
            DispatchQueue.main.async {
                self.onChange?(changedURLs)
            }
        }
        pendingRefresh = workItem
        eventQueue.asyncAfter(deadline: .now() + .milliseconds(350), execute: workItem)
    }
}
