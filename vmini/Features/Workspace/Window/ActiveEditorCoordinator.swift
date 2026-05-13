import AppKit

@MainActor
final class ActiveEditorCoordinator {
    var onOpenURLs: (([URL]) -> Void)?
    var onCursorPositionChanged: (() -> Void)?

    private weak var parentViewController: NSViewController?
    private weak var containerView: NSView?
    private var currentEditorViewController: EditorViewController?

    init(parentViewController: NSViewController, containerView: NSView) {
        self.parentViewController = parentViewController
        self.containerView = containerView
    }

    func display(document: Document?) {
        guard let document else {
            currentEditorViewController?.view.removeFromSuperview()
            currentEditorViewController?.removeFromParent()
            currentEditorViewController = nil
            return
        }

        let editorViewController = document.editorViewController { [weak self] urls in
            self?.onOpenURLs?(urls)
        }
        editorViewController.onCursorPositionChanged = { [weak self] in
            self?.onCursorPositionChanged?()
        }

        guard currentEditorViewController !== editorViewController else {
            editorViewController.focusTextView()
            return
        }

        currentEditorViewController?.view.removeFromSuperview()
        currentEditorViewController?.removeFromParent()

        guard
            let parentViewController,
            let containerView
        else {
            return
        }

        currentEditorViewController = editorViewController
        parentViewController.addChild(editorViewController)
        let editorView = editorViewController.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(editorView)
        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: containerView.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        editorViewController.focusTextView()
    }

    func increaseFontSize() {
        currentEditorViewController?.increaseFontSize()
    }

    func decreaseFontSize() {
        currentEditorViewController?.decreaseFontSize()
    }

    func focusEditor() {
        currentEditorViewController?.focusTextView()
    }

    func toggleLineComment() {
        currentEditorViewController?.toggleLineComment()
    }

    func duplicateSelectedLines() {
        currentEditorViewController?.duplicateSelectedLines()
    }

    func deleteCurrentLine() {
        currentEditorViewController?.deleteCurrentLine()
    }

    @discardableResult
    func moveSelectedLinesUp() -> Bool {
        currentEditorViewController?.moveSelectedLinesUp() ?? false
    }

    @discardableResult
    func moveSelectedLinesDown() -> Bool {
        currentEditorViewController?.moveSelectedLinesDown() ?? false
    }

    func formatJSON() {
        currentEditorViewController?.formatJSONSelectionOrDocument()
    }

    func currentLineNumber() -> Int {
        currentEditorViewController?.currentLineNumber() ?? 1
    }

    @discardableResult
    func goToLine(_ lineNumber: Int) -> Bool {
        currentEditorViewController?.goToLine(lineNumber) ?? false
    }

    func currentCursorPosition() -> EditorCursorPosition? {
        currentEditorViewController?.currentCursorPosition()
    }

    var hasActiveEditor: Bool {
        currentEditorViewController != nil
    }
}
