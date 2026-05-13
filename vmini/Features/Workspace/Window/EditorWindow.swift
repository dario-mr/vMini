import AppKit

final class EditorWindow: NSWindow {
    private let commandDispatcher = AppCommandDispatcher()

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == [.command], characters == "n" {
            commandDispatcher.newDocument(self)
            return true
        }

        if modifiers == [.command], characters == "o" {
            commandDispatcher.openDocumentOrFolder(self)
            return true
        }

        if modifiers == [.command], characters == "s" {
            commandDispatcher.saveCurrentDocument(self)
            return true
        }

        if modifiers == [.command, .shift], characters == "s" {
            commandDispatcher.saveCurrentDocumentAs(self)
            return true
        }

        if modifiers == [.command], characters == "w" {
            commandDispatcher.closeCurrentDocument(self)
            return true
        }

        if modifiers == [.command], characters == "+" || characters == "=" {
            (contentViewController as? EditorContentViewController)?.increaseEditorFontSize()
            return true
        }

        if modifiers == [.command], characters == "-" {
            (contentViewController as? EditorContentViewController)?.decreaseEditorFontSize()
            return true
        }

        if modifiers == [.command], characters == "/" {
            (contentViewController as? EditorContentViewController)?.toggleLineComment()
            return true
        }

        if modifiers == [.command], characters == "d" {
            (contentViewController as? EditorContentViewController)?.duplicateSelectedLines()
            return true
        }

        if modifiers == [.command], event.keyCode == 51 {
            (contentViewController as? EditorContentViewController)?.deleteCurrentLine()
            return true
        }

        if modifiers == [.command], characters == "j" {
            (contentViewController as? EditorContentViewController)?.formatJSON()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
