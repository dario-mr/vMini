import AppKit

@MainActor
final class ActiveEditorCoordinator {
    var onOpenURLs: (([URL]) -> Void)?
    var onCursorPositionChanged: (() -> Void)?
    var onNavigationCheckpoint: ((Document, NSRange, NSRange) -> Void)?

    private weak var parentViewController: NSViewController?
    private weak var containerView: NSView?
    private var currentViewController: NSViewController?
    private var currentEditorViewController: EditorViewController? { currentViewController as? EditorViewController }

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
                guard let self, let document, currentEditorViewController === editor else { return }
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

    func increaseFontSize() {
        currentEditorViewController?.increaseFontSize()
    }

    func decreaseFontSize() {
        currentEditorViewController?.decreaseFontSize()
    }

    func focusEditor() {
        currentEditorViewController?.focusTextView()
        (currentViewController as? ParquetViewController)?.focusTable()
    }

    @discardableResult
    func performSearchAction(_ action: EditorSearchAction) -> Bool {
        currentEditorViewController?.performSearchAction(action) ?? false
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

    var canFormatMarkdownTable: Bool { currentEditorViewController?.canFormatMarkdownTable ?? false }

    func formatMarkdownTable() { currentEditorViewController?.formatMarkdownTable() }

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

    var navigationSelection: NSRange? {
        currentEditorViewController?.navigationSelection
            ?? (currentViewController is ParquetViewController ? NSRange(location: 0, length: 0) : nil)
    }

    func restoreNavigationSelection(_ selection: NSRange) {
        currentEditorViewController?.restoreNavigationSelection(selection)
    }
}
