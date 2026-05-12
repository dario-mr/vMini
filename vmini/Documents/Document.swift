import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let documentSyntaxHighlightingDidChange = Notification.Name("DocumentSyntaxHighlightingDidChange")
}

@MainActor
final class Document: NSDocument {
    static let supportedTypes: [UTType] = [.plainText, .text]

    let sessionIdentifier: UUID

    private var text = ""
    private var typeIdentifier: String?
    private var editorViewController: EditorViewController?
    private let externalChangeWatcher = DocumentFileWatcher()
    private let syntaxOverrideStore: SyntaxOverrideStore
    private var syntaxLanguageOverride: SyntaxLanguage?

    var sidebarTitle: String {
        fileURL?.lastPathComponent ?? displayName
    }

    var shortDisplayTitle: String {
        isDocumentEdited ? "• \(sidebarTitle)" : sidebarTitle
    }

    var windowTitle: String {
        guard let fileURL else {
            return displayName
        }

        return (fileURL.path as NSString).abbreviatingWithTildeInPath
    }

    var autoDetectedSyntaxLanguage: SyntaxLanguage {
        SyntaxLanguageResolver.resolve(
            fileURL: fileURL,
            typeIdentifier: typeIdentifier,
            content: syntaxDetectionContentSample()
        )
    }

    var syntaxLanguage: SyntaxLanguage {
        syntaxLanguageOverride ?? autoDetectedSyntaxLanguage
    }

    var hasSyntaxLanguageOverride: Bool {
        syntaxLanguageOverride != nil
    }

    var syntaxOverrideMenuTitle: String {
        if hasSyntaxLanguageOverride {
            return syntaxLanguage.displayName
        }

        return "\(syntaxLanguage.displayName) (Auto)"
    }

    init(
        sessionIdentifier: UUID = UUID(),
        syntaxOverrideStore: SyntaxOverrideStore? = nil
    ) {
        self.sessionIdentifier = sessionIdentifier
        self.syntaxOverrideStore = syntaxOverrideStore ?? .shared
        self.syntaxLanguageOverride = nil
        super.init()
        hasUndoManager = true
    }

    override var fileURL: URL? {
        didSet {
            Task { @MainActor in
                guard fileURL != oldValue else { return }
                if let fileURL {
                    let newIdentifier = Self.persistenceIdentifier(for: fileURL)
                    if let previousFileURL = oldValue {
                        syntaxOverrideStore.migrateOverride(
                            from: Self.persistenceIdentifier(for: previousFileURL),
                            to: newIdentifier,
                            currentOverride: syntaxLanguageOverride
                        )
                    } else if let syntaxLanguageOverride {
                        syntaxOverrideStore.setOverride(syntaxLanguageOverride, for: newIdentifier)
                    } else {
                        syntaxLanguageOverride = syntaxOverrideStore.override(for: newIdentifier)
                    }
                }
                restartExternalChangeWatcher()
                editorViewController?.syntaxLanguage = syntaxLanguage
                updateWindowTitles()
                notifySyntaxHighlightingDidChange()
                OpenDocumentsStore.postDidChange()
            }
        }
    }

    override class var readableTypes: [String] {
        supportedTypes.map(\.identifier)
    }

    override class var writableTypes: [String] {
        supportedTypes.map(\.identifier)
    }

    override class var autosavesInPlace: Bool {
        false
    }

    override func makeWindowControllers() {
        WorkspaceWindowController.shared.present(document: self)
    }

    override func close() {
        externalChangeWatcher.stop()
        editorViewController = nil
        super.close()
        if OpenDocumentsStore.shared.activeDocument === self {
            OpenDocumentsStore.shared.select(OpenDocumentsStore.shared.documents.first)
        } else {
            OpenDocumentsStore.postDidChange()
        }
    }

    override func save(_ sender: Any?) {
        externalChangeWatcher.stop()
        super.save(sender)
        restartExternalChangeWatcher()
        OpenDocumentsStore.postDidChange()
    }

    override func saveAs(_ sender: Any?) {
        externalChangeWatcher.stop()
        super.saveAs(sender)
        restartExternalChangeWatcher()
        OpenDocumentsStore.postDidChange()
    }

    private func updateWindowTitles() {
        OpenDocumentsStore.postDidChange()
    }

    private func restartExternalChangeWatcher() {
        externalChangeWatcher.watch(fileURL: fileURL) { [weak self] restartWatcher in
            self?.reloadFromDiskAfterExternalChange(restartWatcher: restartWatcher)
        }
    }

    private func reloadFromDiskAfterExternalChange(restartWatcher: Bool) {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let typeName = try NSDocumentController.shared.typeForContents(of: fileURL)
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            try read(from: data, ofType: typeName)
            updateChangeCount(.changeCleared)
            undoManager?.removeAllActions()
            OpenDocumentsStore.postDidChange()

            if restartWatcher {
                externalChangeWatcher.watch(fileURL: fileURL) { [weak self] restartWatcher in
                    self?.reloadFromDiskAfterExternalChange(restartWatcher: restartWatcher)
                }
            }
        } catch {
            NSLog("Could not reload externally changed file %@: %@", fileURL.path as NSString, error.localizedDescription)
        }
    }

    override func write(to url: URL, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            let currentText = editorViewController?.text ?? text
            text = currentText
            return currentText
        }.write(to: url, atomically: true, encoding: .utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        if let decoded = String(data: data, encoding: .utf8) {
            MainActor.assumeIsolated {
                typeIdentifier = typeName
                text = decoded
                editorViewController?.text = decoded
                editorViewController?.syntaxLanguage = syntaxLanguage
                notifySyntaxHighlightingDidChange()
            }
            return
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    func resolvedEditorViewController(onFileSystemURLsDropped: @escaping ([URL]) -> Void) -> EditorViewController {
        if let editorViewController {
            editorViewController.onFileSystemURLsDropped = onFileSystemURLsDropped
            return editorViewController
        }

        let editorViewController = EditorViewController()
        editorViewController.text = text
        editorViewController.syntaxLanguage = syntaxLanguage
        editorViewController.onTextChanged = { [weak self] in
            guard let self else { return }
            let resolvedSyntaxLanguage = syntaxLanguage
            if editorViewController.syntaxLanguage != resolvedSyntaxLanguage {
                editorViewController.syntaxLanguage = resolvedSyntaxLanguage
                notifySyntaxHighlightingDidChange()
            }
            let wasEdited = isDocumentEdited
            updateChangeCount(.changeDone)

            if wasEdited != isDocumentEdited {
                OpenDocumentsStore.postDidChange()
            }
        }
        editorViewController.onFileSystemURLsDropped = onFileSystemURLsDropped
        self.editorViewController = editorViewController
        return editorViewController
    }

    func setSyntaxLanguageOverride(_ language: SyntaxLanguage?) {
        guard syntaxLanguageOverride != language else { return }
        syntaxLanguageOverride = language
        if let persistenceIdentifier {
            syntaxOverrideStore.setOverride(language, for: persistenceIdentifier)
        }
        editorViewController?.syntaxLanguage = syntaxLanguage
        notifySyntaxHighlightingDidChange()
    }

    private func syntaxDetectionContentSample() -> String {
        let sourceText = editorViewController?.text ?? text
        return String(sourceText.prefix(512))
    }

    private var persistenceIdentifier: String? {
        guard let fileURL else {
            return nil
        }

        return Self.persistenceIdentifier(for: fileURL)
    }

    private static func persistenceIdentifier(for fileURL: URL) -> String {
        fileURL.standardizedFileURL.path
    }

    private func notifySyntaxHighlightingDidChange() {
        NotificationCenter.default.post(name: .documentSyntaxHighlightingDidChange, object: self)
    }
}
