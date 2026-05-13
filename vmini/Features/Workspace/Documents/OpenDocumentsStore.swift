import AppKit

@MainActor
final class OpenDocumentsStore {
    struct State {
        let documents: [Document]
        let activeDocument: Document?
    }

    static let shared = OpenDocumentsStore()

    private(set) var documents: [Document] = []
    private(set) var activeDocument: Document?
    private var observers: [UUID: (State) -> Void] = [:]
    private var mutationDepth = 0
    private var pendingNotification = false

    func observe(_ observer: @escaping (State) -> Void) -> ObservationToken {
        let identifier = UUID()
        observers[identifier] = observer
        observer(currentState())
        return ObservationToken { [weak self] in
            self?.observers.removeValue(forKey: identifier)
        }
    }

    func contains(_ document: Document) -> Bool {
        documents.contains(where: { $0 === document })
    }

    func register(_ document: Document, makeActive: Bool = false) {
        let wasInserted = appendIfNeeded(document)
        let didSelect: Bool

        if makeActive || activeDocument == nil {
            didSelect = activeDocument !== document
            activeDocument = document
        } else {
            didSelect = false
        }

        guard wasInserted || didSelect else { return }
        stateDidChange()
    }

    func unregister(_ document: Document) {
        guard let removedIndex = documents.firstIndex(where: { $0 === document }) else {
            return
        }

        documents.remove(at: removedIndex)

        if activeDocument === document {
            activeDocument = documents.isEmpty
                ? nil
                : documents[max(0, min(removedIndex - 1, documents.count - 1))]
        }

        stateDidChange()
    }

    func select(_ document: Document?) {
        let nextDocument = documents.first { candidate in
            guard let document else { return false }
            return candidate === document
        }

        guard activeDocument !== nextDocument else { return }
        activeDocument = nextDocument
        stateDidChange()
    }

    func reorder(document: Document, to destinationIndex: Int) {
        guard let sourceIndex = documents.firstIndex(where: { $0 === document }) else { return }

        let clampedDestinationIndex = min(max(destinationIndex, 0), documents.count - 1)
        guard sourceIndex != clampedDestinationIndex else { return }

        let movedDocument = documents.remove(at: sourceIndex)
        documents.insert(movedDocument, at: clampedDestinationIndex)
        stateDidChange()
    }

    func refresh() {
        stateDidChange()
    }

    func performBatchUpdate(_ updates: () -> Void) {
        mutationDepth += 1
        updates()
        mutationDepth -= 1

        if mutationDepth == 0, pendingNotification {
            pendingNotification = false
            notifyObservers()
        }
    }

    private func appendIfNeeded(_ document: Document) -> Bool {
        guard !contains(document) else { return false }
        documents.append(document)
        return true
    }

    private func currentState() -> State {
        State(documents: documents, activeDocument: activeDocument)
    }

    private func stateDidChange() {
        if mutationDepth > 0 {
            pendingNotification = true
            return
        }

        notifyObservers()
    }

    private func notifyObservers() {
        let state = currentState()
        for observer in observers.values {
            observer(state)
        }
    }
}
