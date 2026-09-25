import AppKit

@MainActor
final class OpenDocumentsStore {
    struct State {
        let documents: [Document]
        let activeDocument: Document?
    }

    static let shared = OpenDocumentsStore()

    private let persistence: WorkspacePersistence
    private var pinnedIdentifiers: Set<String>
    private(set) var documents: [Document] = []
    private(set) var activeDocument: Document?
    private var observers: [UUID: (State) -> Void] = [:]
    private var mutationDepth = 0
    private var pendingNotification = false

    init(persistence: WorkspacePersistence? = nil) {
        let persistence = persistence ?? .shared
        self.persistence = persistence
        pinnedIdentifiers = Set(persistence.pinnedTabIdentifiers)
    }

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

    func isPinned(_ document: Document) -> Bool {
        pinnedIdentifiers.contains(Self.pinIdentifier(for: document))
    }

    func togglePinned(_ document: Document) {
        guard contains(document) else { return }

        let identifier = Self.pinIdentifier(for: document)
        if !pinnedIdentifiers.insert(identifier).inserted {
            pinnedIdentifiers.remove(identifier)
        }
        persistence.pinnedTabIdentifiers = pinnedIdentifiers.sorted()
        keepPinnedDocumentsFirst()
        stateDidChange()
    }

    func migratePinnedIdentifier(from oldURL: URL?, to newURL: URL?, sessionIdentifier: UUID) {
        let oldIdentifier = Self.pinIdentifier(for: oldURL, sessionIdentifier: sessionIdentifier)
        let newIdentifier = Self.pinIdentifier(for: newURL, sessionIdentifier: sessionIdentifier)
        guard oldIdentifier != newIdentifier else { return }

        guard pinnedIdentifiers.remove(oldIdentifier) != nil else { return }
        pinnedIdentifiers.insert(newIdentifier)
        persistence.pinnedTabIdentifiers = pinnedIdentifiers.sorted()
    }

    func register(
        _ document: Document,
        at index: Int? = nil,
        makeActive: Bool = false,
        activateIfEmpty: Bool = true
    ) {
        let wasInserted = insertIfNeeded(document, at: index)
        if wasInserted {
            keepPinnedDocumentsFirst()
        }
        let didSelect: Bool

        if makeActive || (activateIfEmpty && activeDocument == nil) {
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

        var remainingDocuments = documents
        remainingDocuments.remove(at: sourceIndex)
        let pinnedCount = remainingDocuments.filter(isPinned).count
        let minimumDestinationIndex = isPinned(document) ? 0 : pinnedCount
        let maximumDestinationIndex = isPinned(document) ? pinnedCount : remainingDocuments.count
        let clampedDestinationIndex = min(max(destinationIndex, minimumDestinationIndex), maximumDestinationIndex)
        guard sourceIndex != clampedDestinationIndex else { return }

        remainingDocuments.insert(document, at: clampedDestinationIndex)
        documents = remainingDocuments
        stateDidChange()
    }

    func refresh() {
        keepPinnedDocumentsFirst()
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

    private func insertIfNeeded(_ document: Document, at index: Int?) -> Bool {
        guard !contains(document) else { return false }
        if let index {
            documents.insert(document, at: min(max(index, 0), documents.count))
        } else {
            documents.append(document)
        }
        return true
    }

    private func currentState() -> State {
        State(documents: documents, activeDocument: activeDocument)
    }

    private func keepPinnedDocumentsFirst() {
        documents = documents.filter { pinnedIdentifiers.contains(Self.pinIdentifier(for: $0)) }
            + documents.filter { !pinnedIdentifiers.contains(Self.pinIdentifier(for: $0)) }
    }

    private static func pinIdentifier(for document: Document) -> String {
        pinIdentifier(for: document.fileURL, sessionIdentifier: document.sessionIdentifier)
    }

    private static func pinIdentifier(for fileURL: URL?, sessionIdentifier: UUID) -> String {
        let reference: RestorableDocumentReference
        if let fileURL {
            reference = .file(path: fileURL.standardizedFileURL.path)
        } else {
            reference = .untitled(sessionID: sessionIdentifier)
        }
        return reference.persistenceIdentifier
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
