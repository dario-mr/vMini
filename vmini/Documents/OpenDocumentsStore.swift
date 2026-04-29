import AppKit

@MainActor
final class OpenDocumentsStore {
    static let shared = OpenDocumentsStore()
    static let didChangeNotification = Notification.Name("OpenDocumentsStoreDidChange")

    private var documentOrder: [ObjectIdentifier] = []
    private(set) var activeDocument: Document?

    var documents: [Document] {
        let unsortedDocuments = NSDocumentController.shared.documents.compactMap { $0 as? Document }
        syncDocumentOrder(with: unsortedDocuments)

        let orderLookup = Dictionary(uniqueKeysWithValues: documentOrder.enumerated().map { ($1, $0) })
        let originalIndexLookup = Dictionary(uniqueKeysWithValues: unsortedDocuments.enumerated().map { (ObjectIdentifier($1), $0) })
        return unsortedDocuments.sorted { lhs, rhs in
            let lhsOrder = orderLookup[ObjectIdentifier(lhs)] ?? Int.max
            let rhsOrder = orderLookup[ObjectIdentifier(rhs)] ?? Int.max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            return (originalIndexLookup[ObjectIdentifier(lhs)] ?? 0) < (originalIndexLookup[ObjectIdentifier(rhs)] ?? 0)
        }
    }

    func select(_ document: Document?) {
        let nextDocument = documents.first(where: { candidate in
            guard let document else { return false }
            return candidate === document
        })

        guard activeDocument !== nextDocument else { return }
        activeDocument = nextDocument
        Self.postDidChange()
    }

    func reorder(document: Document, to destinationIndex: Int) {
        var orderedDocuments = documents
        guard let sourceIndex = orderedDocuments.firstIndex(where: { $0 === document }) else { return }

        let clampedDestinationIndex = min(max(destinationIndex, 0), orderedDocuments.count - 1)
        guard sourceIndex != clampedDestinationIndex else { return }

        let movedDocument = orderedDocuments.remove(at: sourceIndex)
        orderedDocuments.insert(movedDocument, at: clampedDestinationIndex)
        documentOrder = orderedDocuments.map(ObjectIdentifier.init)
        Self.postDidChange()
    }

    private func syncDocumentOrder(with documents: [Document]) {
        let currentIdentifiers = Set(documents.map(ObjectIdentifier.init))
        documentOrder.removeAll { !currentIdentifiers.contains($0) }

        let knownIdentifiers = Set(documentOrder)
        let missingIdentifiers = documents
            .map(ObjectIdentifier.init)
            .filter { !knownIdentifiers.contains($0) }
        documentOrder.append(contentsOf: missingIdentifiers)
    }

    static func postDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
