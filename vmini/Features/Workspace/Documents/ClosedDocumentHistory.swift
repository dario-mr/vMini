import Foundation

@MainActor
final class ClosedDocumentHistory {
    static let shared = ClosedDocumentHistory()

    private enum Constants {
        static let maximumEntries = 20
    }

    private var references: [RestorableDocumentReference] = []

    var canReopenClosedDocument: Bool {
        !references.isEmpty
    }

    func record(document: Document) {
        let reference = document.restorableReference
        references.removeAll { $0.persistenceIdentifier == reference.persistenceIdentifier }
        references.append(reference)

        if references.count > Constants.maximumEntries {
            references.removeFirst(references.count - Constants.maximumEntries)
        }
    }

    func popMostRecent() -> RestorableDocumentReference? {
        references.popLast()
    }
}
