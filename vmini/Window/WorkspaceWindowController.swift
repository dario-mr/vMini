import AppKit

@MainActor
final class WorkspaceWindowController: NSWindowController {
    static let shared = WorkspaceWindowController()

    private let workspaceViewController = EditorContentViewController()

    private init() {
        let window = EditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = workspaceViewController
        window.titleVisibility = .visible
        window.backgroundColor = AppColors.windowBackground
        window.setFrame(Self.restoredWindowFrame() ?? Self.defaultWindowFrame(), display: false)

        super.init(window: window)
        shouldCascadeWindows = false
        synchronizeWindowState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentsDidChange),
            name: OpenDocumentsStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistWindowFrame),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistWindowFrame),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func present(document: Document) {
        if !OpenDocumentsStore.shared.documents.contains(where: { $0 === document }) {
            NSDocumentController.shared.addDocument(document)
        }

        OpenDocumentsStore.shared.select(document)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        workspaceViewController.focusActiveEditor()
    }

    func open(urls: [URL], activate activeURL: URL? = nil) {
        let standardized = urls.map(\.standardizedFileURL)
        open(
            standardized,
            index: 0,
            activate: activeURL?.standardizedFileURL,
            fallbackDocument: OpenDocumentsStore.shared.activeDocument
        )
    }

    func createUntitledDocument() {
        let document = Document()
        present(document: document)
    }

    func presentSettingsSheet() {
        if window == nil {
            showWindow(nil)
        }

        guard let window else { return }
        SettingsCoordinator.shared.presentSettingsSheet(attachedTo: window)
    }

    func closeCurrentDocument() {
        guard let document = OpenDocumentsStore.shared.activeDocument else { return }
        close(document: document)
    }

    func close(document: Document) {
        let documents = OpenDocumentsStore.shared.documents
        let closedIndex = documents.firstIndex(where: { $0 === document }) ?? 0
        let wasActive = OpenDocumentsStore.shared.activeDocument === document
        let remaining = documents.filter { $0 !== document }
        document.close()

        if wasActive {
            let nextSelection: Document?
            if remaining.isEmpty {
                nextSelection = nil
            } else {
                let targetIndex = max(0, min(closedIndex - 1, remaining.count - 1))
                nextSelection = remaining[targetIndex]
            }
            OpenDocumentsStore.shared.select(nextSelection)
        } else {
            OpenDocumentsStore.postDidChange()
        }

        if remaining.isEmpty {
            synchronizeWindowState()
        }
    }

    @objc
    private func handleDocumentsDidChange() {
        synchronizeWindowState()
    }

    @objc
    private func persistWindowFrame() {
        guard let window else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: UserDefaultsKeys.workspaceWindowFrame)
    }

    @objc
    private func handleThemeDidChange() {
        window?.backgroundColor = AppColors.windowBackground
    }

    private static func defaultWindowFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        let size = NSSize(
            width: min(1000, visibleFrame.width),
            height: min(700, visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func restoredWindowFrame() -> NSRect? {
        guard
            let storedFrame = UserDefaults.standard.string(forKey: UserDefaultsKeys.workspaceWindowFrame),
            let frame = windowFrame(from: storedFrame)
        else {
            return nil
        }

        return constrainedWindowFrame(frame)
    }

    private static func windowFrame(from storedFrame: String) -> NSRect? {
        let rect = NSRectFromString(storedFrame)
        if rect.width > 0, rect.height > 0 {
            return rect
        }

        let values = storedFrame
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }
        guard values.count >= 4, values[2] > 0, values[3] > 0 else {
            return nil
        }

        return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private static func constrainedWindowFrame(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens
            .max { lhs, rhs in
                area(of: lhs.visibleFrame.intersection(frame)) < area(of: rhs.visibleFrame.intersection(frame))
            } ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            return frame
        }

        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        return NSRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }

    private static func area(of rect: NSRect) -> CGFloat {
        max(rect.width, 0) * max(rect.height, 0)
    }

    private func open(_ urls: [URL], index: Int, activate activeURL: URL?, fallbackDocument: Document?) {
        guard index < urls.count else {
            if
                let activeURL,
                let document = NSDocumentController.shared.document(for: activeURL) as? Document
            {
                present(document: document)
            } else if
                let fallbackDocument,
                OpenDocumentsStore.shared.documents.contains(where: { $0 === fallbackDocument })
            {
                present(document: fallbackDocument)
            } else if let first = OpenDocumentsStore.shared.documents.first {
                present(document: first)
            } else {
                synchronizeWindowState()
            }
            return
        }

        let url = urls[index]

        do {
            let document = try openDocument(at: url)

            if activeURL == nil, index == urls.count - 1 {
                present(document: document)
            } else {
                OpenDocumentsStore.postDidChange()
            }
        } catch {
            NSLog("Could not open file %@: %@", url.path as NSString, error.localizedDescription)
        }

        open(urls, index: index + 1, activate: activeURL, fallbackDocument: fallbackDocument)
    }

    private func openDocument(at url: URL) throws -> Document {
        let standardizedURL = url.standardizedFileURL

        if let existing = NSDocumentController.shared.document(for: standardizedURL) as? Document {
            return existing
        }

        let document = Document()
        let typeName = try inferredTypeForDocument(at: standardizedURL)
        let data = try Data(contentsOf: standardizedURL, options: [.mappedIfSafe])

        try document.read(from: data, ofType: typeName)
        document.fileURL = standardizedURL
        document.updateChangeCount(.changeCleared)
        document.undoManager?.removeAllActions()
        NSDocumentController.shared.addDocument(document)
        return document
    }

    private func inferredTypeForDocument(at url: URL) throws -> String {
        if let controller = NSDocumentController.shared as? DocumentController {
            return try controller.typeForContents(of: url)
        }

        return try DocumentController().typeForContents(of: url)
    }

    private func synchronizeWindowState() {
        let title = OpenDocumentsStore.shared.activeDocument?.windowTitle ?? "vMini"
        window?.title = title
        window?.representedURL = OpenDocumentsStore.shared.activeDocument?.fileURL
    }
}
