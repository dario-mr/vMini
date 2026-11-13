import AppKit

@MainActor
final class ActiveEditorCoordinator {
    var onOpenURLs: (([URL]) -> Void)?
    var onCursorPositionChanged: (() -> Void)?
    var onNavigationCheckpoint: ((Document, NSRange, NSRange) -> Void)?

    private weak var parentViewController: NSViewController?
    private weak var containerView: NSView?
    private var currentViewController: NSViewController?
    var activeEditor: EditorViewController? { currentViewController as? EditorViewController }

    init(parentViewController: NSViewController, containerView: NSView) {
        self.parentViewController = parentViewController
        self.containerView = containerView
    }

    func display(document: Document?) {
        guard let document else {
            currentViewController?.view.removeFromSuperview()
            currentViewController?.removeFromParent()
            currentViewController = nil
            return
        }

        let controller: NSViewController
        if let parquetController = document.parquetViewController() {
            controller = parquetController
        } else {
            let editor = document.editorViewController { [weak self] urls in self?.onOpenURLs?(urls) }
            editor.onCursorPositionChanged = { [weak self] in self?.onCursorPositionChanged?() }
            editor.onNavigationCheckpoint = { [weak self, weak document, weak editor] before, after in
                guard let self, let document, activeEditor === editor else { return }
                onNavigationCheckpoint?(document, before, after)
            }
            controller = editor
        }
        guard currentViewController !== controller else {
            focusEditor()
            return
        }
        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()
        guard let parentViewController, let containerView else { return }
        currentViewController = controller
        parentViewController.addChild(controller)
        let contentView = controller.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        focusEditor()
    }

    func focusEditor() {
        activeEditor?.focusTextView()
        (currentViewController as? ParquetViewController)?.focusTable()
    }

    var navigationSelection: NSRange? {
        activeEditor?.navigationSelection
            ?? (currentViewController is ParquetViewController ? NSRange(location: 0, length: 0) : nil)
    }
}
