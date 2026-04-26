import AppKit

@MainActor
final class OpenDocumentsStore {
    static let shared = OpenDocumentsStore()
    static let didChangeNotification = Notification.Name("OpenDocumentsStoreDidChange")

    var documents: [Document] {
        NSDocumentController.shared.documents.compactMap { $0 as? Document }
    }

    static func postDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
