import AppKit

final class EditorWindowController: NSWindowController {
    init(document: Document, editorViewController: EditorViewController) {
        let window = EditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = EditorContentViewController(
            document: document,
            editorViewController: editorViewController
        )
        window.titleVisibility = .visible
        window.tabbingMode = .preferred
        window.backgroundColor = NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.17, alpha: 1.0)

        super.init(window: window)
        shouldCascadeWindows = true
        updateTitles(for: document)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        guard let document = document as? Document else {
            return super.windowTitle(forDocumentDisplayName: displayName)
        }

        return document.windowTitle
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()

        guard let document = document as? Document else {
            return
        }

        applyTitles(for: document)
    }

    func updateTitles(for document: Document) {
        synchronizeWindowTitleWithDocumentName()
    }

    private func applyTitles(for document: Document) {
        window?.representedURL = document.fileURL
        window?.tab.title = document.sidebarTitle
    }

    static func refreshTabGroupTitles(for window: NSWindow?) {
        guard let window else { return }

        if let tabGroup = window.tabGroup {
            for tabbedWindow in tabGroup.windows {
                guard
                    let controller = tabbedWindow.windowController as? EditorWindowController,
                    let document = controller.document as? Document
                else {
                    continue
                }

                controller.applyTitles(for: document)
            }
            return
        }

        guard
            let controller = window.windowController as? EditorWindowController,
            let document = controller.document as? Document
        else {
            return
        }

        controller.applyTitles(for: document)
    }
}
