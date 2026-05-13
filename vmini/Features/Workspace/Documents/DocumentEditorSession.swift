import AppKit

@MainActor
final class DocumentEditorSession {
    private var editorViewController: EditorViewController?

    func resolveEditorViewController(
        text: String,
        syntaxLanguage: SyntaxLanguage,
        onFileSystemURLsDropped: @escaping ([URL]) -> Void,
        onTextChanged: @escaping (EditorViewController) -> Void
    ) -> EditorViewController {
        if let editorViewController {
            editorViewController.onFileSystemURLsDropped = onFileSystemURLsDropped
            return editorViewController
        }

        let editorViewController = EditorViewController()
        editorViewController.text = text
        editorViewController.syntaxLanguage = syntaxLanguage
        editorViewController.onTextChanged = { [weak editorViewController] in
            guard let editorViewController else { return }
            onTextChanged(editorViewController)
        }
        editorViewController.onFileSystemURLsDropped = onFileSystemURLsDropped
        self.editorViewController = editorViewController
        return editorViewController
    }

    func update(text: String, syntaxLanguage: SyntaxLanguage) {
        editorViewController?.text = text
        editorViewController?.syntaxLanguage = syntaxLanguage
    }

    func currentEditorText() -> String? {
        editorViewController?.text
    }

    func clear() {
        editorViewController = nil
    }
}
