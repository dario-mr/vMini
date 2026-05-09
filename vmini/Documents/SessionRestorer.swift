import AppKit

@MainActor
enum SessionRestorer {
    private static var isTerminationSnapshotLocked = false

    static func saveOpenFiles() {
        guard !isTerminationSnapshotLocked else { return }

        let openFilePaths = OpenDocumentsStore.shared.documents.compactMap { document -> String? in
            document.fileURL?.standardizedFileURL.path
        }
        let activeFilePath = OpenDocumentsStore.shared.activeDocument?.fileURL?.standardizedFileURL.path

        UserDefaults.standard.set(openFilePaths, forKey: UserDefaultsKeys.sessionRestorerOpenFilePaths)
        UserDefaults.standard.set(activeFilePath, forKey: UserDefaultsKeys.sessionRestorerActiveFilePath)
    }

    static func prepareForTermination() {
        saveOpenFiles()
        isTerminationSnapshotLocked = true
    }

    static func cancelTermination() {
        isTerminationSnapshotLocked = false
        saveOpenFiles()
    }

    @discardableResult
    static func reopenLastFiles() -> Bool {
        guard let storedPaths = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.sessionRestorerOpenFilePaths) else {
            return false
        }

        let urls = storedPaths
            .map(URL.init(fileURLWithPath:))
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return false }

        let activeURL = UserDefaults.standard
            .string(forKey: UserDefaultsKeys.sessionRestorerActiveFilePath)
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
        WorkspaceWindowController.shared.open(urls: urls, activate: activeURL)
        return true
    }
}
