import AppKit

final class EditorContentViewController: NSViewController {
    private enum Constants {
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarMaxWidth: CGFloat = 420
        static let sidebarDefaultWidth: CGFloat = 300
        static let resizeHandleWidth: CGFloat = 12
    }

    private let sidebarViewController: OpenFilesSidebarViewController
    private let editorViewController: EditorViewController
    private let resizeHandle = ResizeHandleView()
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var dragStartWidth: CGFloat = 0

    init(document: Document, editorViewController: EditorViewController) {
        self.sidebarViewController = OpenFilesSidebarViewController(initialDocument: document)
        self.editorViewController = editorViewController
        super.init(nibName: nil, bundle: nil)
        editorViewController.onFileSystemURLsDropped = { [weak self] urls in
            self?.openFileSystemURLs(urls)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let contentView = FileDropContentView()
        contentView.dropDelegate = self
        view = contentView
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.13, alpha: 1.0).cgColor

        addChild(sidebarViewController)
        addChild(editorViewController)

        let sidebarView = sidebarViewController.view
        let editorView = editorViewController.view
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        editorView.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(sidebarView)
        view.addSubview(editorView)
        view.addSubview(resizeHandle)

        let widthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: storedSidebarWidth())
        sidebarWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            widthConstraint,

            editorView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: view.topAnchor),
            editorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            resizeHandle.centerXAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: view.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: Constants.resizeHandleWidth),
        ])

        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleSidebarResize(_:)))
        resizeHandle.addGestureRecognizer(panGesture)
        resizeHandle.cursor = .resizeLeftRight
    }

    func increaseEditorFontSize() {
        editorViewController.increaseFontSize()
    }

    func decreaseEditorFontSize() {
        editorViewController.decreaseFontSize()
    }

    private func storedSidebarWidth() -> CGFloat {
        let width = UserDefaults.standard.double(forKey: UserDefaultsKeys.openFilesSidebarWidth)
        guard width > 0 else { return Constants.sidebarDefaultWidth }
        return min(max(width, Constants.sidebarMinWidth), Constants.sidebarMaxWidth)
    }

    @objc
    private func handleSidebarResize(_ gestureRecognizer: NSPanGestureRecognizer) {
        guard let sidebarWidthConstraint else { return }

        switch gestureRecognizer.state {
        case .began:
            dragStartWidth = sidebarWidthConstraint.constant
        case .changed:
            let translation = gestureRecognizer.translation(in: view).x
            let proposedWidth = dragStartWidth + translation
            sidebarWidthConstraint.constant = min(max(proposedWidth, Constants.sidebarMinWidth), Constants.sidebarMaxWidth)
        case .ended, .cancelled:
            let finalWidth = min(max(sidebarWidthConstraint.constant, Constants.sidebarMinWidth), Constants.sidebarMaxWidth)
            sidebarWidthConstraint.constant = finalWidth
            UserDefaults.standard.set(finalWidth, forKey: UserDefaultsKeys.openFilesSidebarWidth)
        default:
            break
        }
    }
}

extension EditorContentViewController: FileDropContentViewDelegate {
    func fileDropContentView(_ view: FileDropContentView, didReceiveFileSystemURLs urls: [URL]) {
        openFileSystemURLs(urls)
    }

    private func openFileSystemURLs(_ urls: [URL]) {
        guard let targetWindow = view.window else { return }
        OpenURLRouter.open(urls, tabbedIn: targetWindow)
    }
}
