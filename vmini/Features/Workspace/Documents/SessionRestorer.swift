import AppKit

@MainActor
enum SessionRestorer {
    private static let manager = WorkspaceSessionManager(
        persistence: .shared,
        openDocumentsStore: .shared,
        documentRouter: WorkspaceDocumentCoordinator.shared
    )

    static func saveOpenFiles() {
        manager.saveOpenFiles()
    }

    static func prepareForTermination() {
        manager.prepareForTermination()
    }

    static func cancelTermination() {
        manager.cancelTermination()
    }

    @discardableResult
    static func reopenLastFiles() -> Bool {
        manager.reopenLastFiles()
    }
}
