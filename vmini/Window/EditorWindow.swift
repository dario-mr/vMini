import AppKit

final class EditorWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == [.command], characters == "n" {
            NSDocumentController.shared.newDocument(self)
            return true
        }

        if modifiers == [.command], characters == "o" {
            NSDocumentController.shared.openDocument(self)
            return true
        }

        if modifiers == [.command], characters == "s" {
            NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: self)
            return true
        }

        if modifiers == [.command, .shift], characters == "s" {
            NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: self)
            return true
        }

        if modifiers == [.command], characters == "w" {
            performClose(self)
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
