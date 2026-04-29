import AppKit

final class EditorWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == [.command], characters == "n" {
            (NSApp.delegate as? AppDelegate)?.newDocument(self)
            return true
        }

        if modifiers == [.command], characters == "o" {
            (NSApp.delegate as? AppDelegate)?.openDocumentOrFolder(self)
            return true
        }

        if modifiers == [.command], characters == "s" {
            (NSApp.delegate as? AppDelegate)?.saveCurrentDocument(self)
            return true
        }

        if modifiers == [.command, .shift], characters == "s" {
            (NSApp.delegate as? AppDelegate)?.saveCurrentDocumentAs(self)
            return true
        }

        if modifiers == [.command], characters == "w" {
            (NSApp.delegate as? AppDelegate)?.closeCurrentDocument(self)
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

        return super.performKeyEquivalent(with: event)
    }
}
