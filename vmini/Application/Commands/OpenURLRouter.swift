import AppKit

@MainActor
enum OpenURLRouter {
    static func open(_ urls: [URL], tabbedIn targetWindow: NSWindow?) {
        let folders = urls.filter(isDirectory)
        let files = urls.filter { !isDirectory($0) }

        OpenFoldersStore.shared.add(folders)
        WorkspaceDocumentCoordinator.shared.open(urls: files, activate: files.last)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
