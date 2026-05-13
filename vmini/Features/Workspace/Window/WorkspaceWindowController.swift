import AppKit

@MainActor
final class WorkspaceWindowController: NSWindowController {
    static let shared = WorkspaceWindowController()

    private let workspaceViewController = EditorContentViewController()
    private let documentCoordinator = WorkspaceDocumentCoordinator.shared
    private let framePersistence = WindowFramePersistence()
    private var documentsObservation: ObservationToken?
    private var themeObservation: ObservationToken?

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
        window.setFrame(framePersistence.restoredWindowFrame() ?? framePersistence.defaultWindowFrame(), display: false)

        super.init(window: window)
        shouldCascadeWindows = false
        documentCoordinator.onDocumentPresentationRequested = { [weak self] in
            self?.showWorkspaceWindow()
        }
        documentCoordinator.onNeedsWindowStateRefresh = { [weak self] in
            self?.synchronizeWindowState()
        }
        synchronizeWindowState()

        documentsObservation = OpenDocumentsStore.shared.observe { [weak self] _ in
            self?.synchronizeWindowState()
        }
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
        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.window?.backgroundColor = AppColors.windowBackground
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func presentSettingsSheet() {
        if window == nil {
            showWindow(nil)
        }

        guard let window else { return }
        SettingsCoordinator.shared.presentSettingsSheet(attachedTo: window)
    }

    func closeCurrentDocument() {
        documentCoordinator.closeCurrentDocument()
    }

    func close(document: Document) {
        documentCoordinator.close(document: document)
    }

    func reopenMostRecentClosedDocument() {
        documentCoordinator.reopenMostRecentClosedDocument()
    }

    @objc
    private func persistWindowFrame() {
        framePersistence.persist(window: window)
    }

    private func synchronizeWindowState() {
        window?.title = documentCoordinator.activeWindowTitle
        window?.representedURL = documentCoordinator.activeRepresentedURL
    }

    private func showWorkspaceWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        workspaceViewController.focusActiveEditor()
    }
}
