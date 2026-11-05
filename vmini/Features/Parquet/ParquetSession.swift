import Foundation

@MainActor
final class ParquetSession {
    enum State {
        case loading
        case loaded(ParquetPage)
        case failed(String)
        case closed
    }

    private(set) var state: State = .loading
    private var task: Task<Void, Never>?
    private var observers: [UUID: () -> Void] = [:]
    private(set) var url: URL

    init(url: URL) {
        self.url = url
        reload(from: url)
    }

    deinit { task?.cancel() }

    func observe(_ observer: @escaping () -> Void) -> ObservationToken {
        let id = UUID()
        observers[id] = observer
        observer()
        return ObservationToken { [weak self] in self?.observers.removeValue(forKey: id) }
    }

    func reload(from url: URL) {
        task?.cancel()
        self.url = url
        state = .loading
        notifyObservers()
        task = Task { [weak self] in
            let load = Task.detached(priority: .userInitiated) { try await ParquetPage.load(from: url) }
            let result = await withTaskCancellationHandler {
                await load.result
            } onCancel: {
                load.cancel()
            }
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let page): state = .loaded(page)
            case .failure(let error): state = .failed(error.localizedDescription)
            }
            task = nil
            notifyObservers()
        }
    }

    func close() {
        task?.cancel()
        task = nil
        state = .closed
        notifyObservers()
    }

    var statusText: String {
        switch state {
        case .loading: return "Loading Parquet…"
        case .loaded(let page):
            return "Showing \(page.rows.count.formatted()) of \(page.totalRows.formatted()) rows · \(page.columns.count.formatted()) columns"
        case .failed: return "Could not load Parquet"
        case .closed: return ""
        }
    }

    private func notifyObservers() {
        for observer in observers.values { observer() }
    }
}
