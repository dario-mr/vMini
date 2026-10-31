import Darwin
import Foundation

final class SidebarFolderWatcher: Sendable {
    typealias ChangeHandler = @MainActor @Sendable ([URL]) -> Void

    private let eventQueue: DispatchQueue
    private let state: State

    init() {
        let eventQueue = DispatchQueue(label: "vmini.sidebar-folder-watcher", qos: .utility)
        self.eventQueue = eventQueue
        state = State(eventQueue: eventQueue)
    }

    deinit {
        let state = state
        eventQueue.async { state.stop() }
    }

    @MainActor
    func watch(directoryURLs: [URL], onChange: @escaping ChangeHandler) {
        var uniqueURLs: [String: URL] = [:]
        for url in directoryURLs {
            let standardizedURL = url.standardizedFileURL
            uniqueURLs[standardizedURL.path] = standardizedURL
        }

        let state = state
        eventQueue.async {
            state.watch(directoryURLsByPath: uniqueURLs, onChange: onChange)
        }
    }

    @MainActor
    func stop() {
        let state = state
        eventQueue.async { state.stop() }
    }

    // Mutable watcher state stays on eventQueue; isCurrent synchronizes reads through it.
    private final class State: @unchecked Sendable {
        private struct WatchedDirectory {
            let identifier: UUID
            let source: DispatchSourceFileSystemObject
        }

        private let eventQueue: DispatchQueue
        private var generation: UInt64 = 0
        private var watchersByPath: [String: WatchedDirectory] = [:]
        private var pendingRefresh: DispatchWorkItem?
        private var pendingChangedDirectoryPaths: Set<String> = []
        private var onChange: ChangeHandler?

        init(eventQueue: DispatchQueue) {
            self.eventQueue = eventQueue
        }

        func watch(directoryURLsByPath: [String: URL], onChange: @escaping ChangeHandler) {
            generation &+= 1
            pendingRefresh?.cancel()
            pendingRefresh = nil
            pendingChangedDirectoryPaths.removeAll()
            self.onChange = onChange

            for path in Array(watchersByPath.keys) where directoryURLsByPath[path] == nil {
                watchersByPath.removeValue(forKey: path)?.source.cancel()
            }

            for (path, url) in directoryURLsByPath where watchersByPath[path] == nil {
                guard let watcher = makeWatcher(for: url, path: path) else { continue }
                watchersByPath[path] = watcher
                watcher.source.resume()
            }
        }

        func stop() {
            generation &+= 1
            pendingRefresh?.cancel()
            pendingRefresh = nil
            pendingChangedDirectoryPaths.removeAll()
            for watcher in watchersByPath.values {
                watcher.source.cancel()
            }
            watchersByPath.removeAll()
            onChange = nil
        }

        func isCurrent(_ expectedGeneration: UInt64) -> Bool {
            eventQueue.sync { generation == expectedGeneration }
        }

        private func makeWatcher(for directoryURL: URL, path: String) -> WatchedDirectory? {
            let fileDescriptor = open(directoryURL.path, O_EVTONLY)
            guard fileDescriptor >= 0 else { return nil }

            let identifier = UUID()
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename],
                queue: eventQueue
            )
            watcher.setEventHandler { [weak self] in
                self?.scheduleRefresh(for: path, watcherIdentifier: identifier)
            }
            watcher.setCancelHandler { [fileDescriptor] in
                Darwin.close(fileDescriptor)
            }
            return WatchedDirectory(identifier: identifier, source: watcher)
        }

        private func scheduleRefresh(for path: String, watcherIdentifier: UUID) {
            guard watchersByPath[path]?.identifier == watcherIdentifier else { return }

            pendingChangedDirectoryPaths.insert(path)
            pendingRefresh?.cancel()
            let generation = generation
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.generation == generation else { return }
                let changedURLs = self.pendingChangedDirectoryPaths.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                }
                self.pendingChangedDirectoryPaths.removeAll()
                self.pendingRefresh = nil
                guard let onChange = self.onChange else { return }

                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(generation) else { return }
                    onChange(changedURLs)
                }
            }
            pendingRefresh = workItem
            eventQueue.asyncAfter(deadline: .now() + .milliseconds(350), execute: workItem)
        }
    }
}
