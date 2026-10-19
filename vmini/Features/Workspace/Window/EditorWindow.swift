import AppKit

final class EditorWindow: NSWindow {
    private let commandDispatcher = AppCommandDispatcher()

    override func sendEvent(_ event: NSEvent) {
        if (event.type == .otherMouseDown || event.type == .otherMouseUp),
           event.buttonNumber == 3 || event.buttonNumber == 4,
           attachedSheet == nil,
           let workspace = contentViewController as? EditorContentViewController {
            if event.type == .otherMouseDown {
                if event.buttonNumber == 3 { workspace.navigateBack() }
                else { workspace.navigateForward() }
            }
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        if let action = EditorSearchAction.action(for: event),
           (contentViewController as? EditorContentViewController)?.performSearchAction(action) == true {
            return true
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == [.command, .shift], characters == "z" {
            if let undoManager = firstResponder?.undoManager, undoManager.canRedo {
                undoManager.redo()
            }
            return true
        }

        if modifiers == [.command], characters == "[" || characters == "]", attachedSheet == nil,
           let workspace = contentViewController as? EditorContentViewController {
            if characters == "[" { workspace.navigateBack() }
            else { workspace.navigateForward() }
            return true
        }

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
