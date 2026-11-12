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
    private(set) var query = ParquetQuery()
    private(set) var page: ParquetPage?
    private(set) var resultRevision = 0
    private(set) var countError: String?
    var isCounting: Bool {
        if case .loaded(let page) = state { return page.matchingRows == nil && countError == nil }
        return false
    }

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
        self.url = url
        page = nil
        resultRevision += 1
        load(reconcileSchema: true)
    }

    func apply(_ query: ParquetQuery, debounce: Bool = false) {
        if case .closed = state { return }
        guard query != self.query else { return }
        self.query = query
        load(debounce: debounce)
    }

    func cycleSort(column: ParquetPage.Column) {
        guard ParquetColumnKind(type: column.type) != .other else { return }
        var query = query
        query.cycleSort(column: column)
        apply(query)
    }

    func clearFilters() {
        var query = query
        query.search = ""
        query.filters = [:]
        apply(query)
    }

    private func load(debounce: Bool = false, reconcileSchema: Bool = false) {
        task?.cancel()
        let url = url
        let query = query
        countError = nil
        state = .loading
        notifyObservers()
        task = Task { [weak self] in
            if debounce {
                do { try await Task.sleep(nanoseconds: 260_000_000) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            let load = Task.detached(priority: .userInitiated) {
                try await ParquetPage.load(from: url, query: query, reconcileSchema: reconcileSchema, countMatches: false)
            }
            let result = await withTaskCancellationHandler {
                await load.result
            } onCancel: {
                load.cancel()
            }
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let page):
                self.page = page
                self.query = page.query
                resultRevision += 1
                state = .loaded(page)
            case .failure(let error): state = .failed(error.localizedDescription)
            }
            task = nil
            notifyObservers()
            if isCounting { count(url: url) }
        }
    }

    // Counting can scan the whole file, so it runs after the rows are shown and shares their cancellation.
    private func count(url: URL) {
        guard let page else { return }
        task = Task { [weak self] in
            let count = Task.detached(priority: .userInitiated) {
                try await ParquetPage.countMatches(in: url, query: page.query, columns: page.columns)
            }
            let result = await withTaskCancellationHandler {
                await count.result
            } onCancel: {
                count.cancel()
            }
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let matchingRows): self.page?.matchingRows = matchingRows
            case .failure(let error): countError = error.localizedDescription
            }
            if let current = self.page { state = .loaded(current) }
            task = nil
            notifyObservers()
        }
    }

    func close() {
        task?.cancel()
        task = nil
        page = nil
        query = ParquetQuery()
        resultRevision += 1
        state = .closed
        notifyObservers()
    }

    var statusText: String {
        guard let page else { return "" }
        guard page.query.isFiltered else { return Self.rowCountText(totalRows: page.totalRows) }
        if let matchingRows = page.matchingRows { return Self.rowCountText(totalRows: page.totalRows, matchingRows: matchingRows) }
        // Rows appear before their count finishes, so say why only the total is known.
        let prefix = countError == nil ? "Counting matches…" : "Could not count matches"
        return "\(prefix) · \(Self.rowCountText(totalRows: page.totalRows))"
    }

    static func rowCountText(totalRows: Int64, matchingRows: Int64? = nil) -> String {
        let prefix = matchingRows.map { "\($0.localizedCount) of " } ?? ""
        return "\(prefix)\(totalRows.localizedCount) rows"
    }

    private func notifyObservers() {
        for observer in observers.values { observer() }
    }

}

extension BinaryInteger {
    /// `formatted()` ignores the user's custom number format in System Settings; NumberFormatter honors it.
    var localizedCount: String { NumberFormatter.localizedString(from: NSNumber(value: Int64(self)), number: .decimal) }
}
