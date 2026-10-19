import AppKit
import XCTest
@testable import vmini

@MainActor
final class WorkspaceNavigationTests: XCTestCase {
    func testHistoryRestoresCursorLocationsAcrossTabsInBothDirections() throws {
        let (workspace, store) = makeWorkspace()
        let first = makeDocument(store)
        let second = makeDocument(store)
        store.register(first)
        let firstEditor = editor(first)
        firstEditor.text = "one\ntwo\nthree\nfour"
        XCTAssertTrue(workspace.goToLine(3))
        XCTAssertTrue(workspace.goToLine(4))
        store.register(second)
        store.select(second)
        let secondEditor = editor(second)
        secondEditor.text = "a\nb\nc"
        XCTAssertTrue(workspace.goToLine(2))

        workspace.navigateBack()
        XCTAssertTrue(store.activeDocument === second)
        XCTAssertEqual(secondEditor.navigationSelection.location, 0)
        workspace.navigateBack()
        XCTAssertTrue(store.activeDocument === first)
        XCTAssertEqual(firstEditor.currentLineNumber(), 4)
        workspace.navigateBack()
        XCTAssertEqual(firstEditor.currentLineNumber(), 3)
        workspace.navigateBack()
        XCTAssertEqual(firstEditor.navigationSelection.location, 0)
        XCTAssertFalse(workspace.canGoBack)

        workspace.navigateForward()
        XCTAssertEqual(firstEditor.currentLineNumber(), 3)
        workspace.navigateForward()
        XCTAssertEqual(firstEditor.currentLineNumber(), 4)
        workspace.navigateForward()
        XCTAssertTrue(store.activeDocument === second)
        XCTAssertEqual(secondEditor.navigationSelection.location, 0)
        workspace.navigateForward()
        XCTAssertEqual(secondEditor.currentLineNumber(), 2)
        XCTAssertFalse(workspace.canGoForward)
    }

    func testNewNavigationAfterBackDiscardsForwardHistoryButNoOpDoesNot() {
        let (workspace, store) = makeWorkspace()
        let document = makeDocument(store)
        store.register(document)
        editor(document).text = "one\ntwo\nthree"
        workspace.goToLine(2)
        workspace.goToLine(3)
        workspace.navigateBack()
        XCTAssertTrue(workspace.canGoForward)
        workspace.goToLine(2)
        XCTAssertTrue(workspace.canGoForward)
        workspace.goToLine(1)
        XCTAssertFalse(workspace.canGoForward)
        workspace.navigateBack()
        XCTAssertEqual(editor(document).currentLineNumber(), 2)
    }

    func testClosingTabsPrunesHistoryAndDoesNotReopenThem() {
        let (workspace, store) = makeWorkspace()
        let first = makeDocument(store)
        let second = makeDocument(store)
        let third = makeDocument(store)
        store.register(first)
        store.register(second)
        store.select(second)
        store.register(third)
        store.select(third)
        store.unregister(second)
        workspace.navigateBack()
        XCTAssertTrue(store.activeDocument === first)
        workspace.navigateForward()
        XCTAssertTrue(store.activeDocument === third)
        store.unregister(first)
        XCTAssertFalse(workspace.canGoBack)
    }

    func testSearchCreatesCheckpointsWithinTheSameLine() {
        let (workspace, store) = makeWorkspace()
        let document = makeDocument(store)
        store.register(document)
        let editor = editor(document)
        editor.text = "foo bar foo"
        let search = editor.searchController
        search.panel.searchField.stringValue = "foo"
        workspace.performSearchAction(.find)
        workspace.performSearchAction(.next)
        XCTAssertEqual(editor.navigationSelection, NSRange(location: 8, length: 3))
        workspace.navigateBack()
        XCTAssertEqual(editor.navigationSelection, NSRange(location: 0, length: 3))
        workspace.navigateForward()
        XCTAssertEqual(editor.navigationSelection, NSRange(location: 8, length: 3))
    }

    func testTypingDoesNotAddStopsAndBackPreservesTheCurrentPositionForForward() throws {
        let (workspace, store) = makeWorkspace()
        let document = makeDocument(store)
        store.register(document)
        let editor = editor(document)
        editor.text = "one\ntwo"
        workspace.goToLine(2)
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        textView.insertText("😀", replacementRange: textView.selectedRange())
        let selectionAfterTyping = textView.selectedRange()
        workspace.navigateBack()
        XCTAssertEqual(editor.navigationSelection.location, 0)
        XCTAssertFalse(workspace.canGoBack)
        workspace.navigateForward()
        XCTAssertEqual(editor.navigationSelection, selectionAfterTyping)
        XCTAssertEqual(editor.text, "one\n😀two")
    }

    func testRestoringOldPositionClampsToShortenedDocument() {
        let (workspace, store) = makeWorkspace()
        let document = makeDocument(store)
        store.register(document)
        let editor = editor(document)
        editor.text = "one\ntwo\nthree"
        workspace.goToLine(3)
        workspace.goToLine(1)
        editor.text = "😀"
        workspace.navigateBack()
        XCTAssertEqual(editor.navigationSelection, NSRange(location: 2, length: 0))
        XCTAssertEqual(editor.text, "😀")
    }

    func testDocumentJumpKeysCreateCheckpoints() throws {
        let (workspace, store) = makeWorkspace()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = workspace
        defer { window.orderOut(nil) }
        let document = makeDocument(store)
        store.register(document)
        let editor = editor(document)
        editor.text = "one\ntwo\nthree"
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        window.makeFirstResponder(textView)
        textView.keyDown(with: try keyEvent("\u{f701}", code: 125, modifiers: [.command, .function]))
        XCTAssertEqual(editor.navigationSelection.location, (editor.text as NSString).length)
        workspace.navigateBack()
        XCTAssertEqual(editor.navigationSelection.location, 0)
        workspace.navigateForward()
        XCTAssertEqual(editor.navigationSelection.location, (editor.text as NSString).length)
    }

    func testBrowserShortcutsAndRawMouseButtonsNavigateOncePerClick() throws {
        let (workspace, store) = makeWorkspace()
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = workspace
        defer { window.orderOut(nil) }
        let document = makeDocument(store)
        store.register(document)
        let editor = editor(document)
        editor.text = "one\ntwo\nthree"
        workspace.goToLine(2)
        workspace.goToLine(3)
        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent("[", code: 33, modifiers: .command)))
        XCTAssertEqual(editor.currentLineNumber(), 2)
        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent("]", code: 30, modifiers: .command)))
        XCTAssertEqual(editor.currentLineNumber(), 3)

        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            window.sendEvent(try mouseEvent(type, button: 3))
            XCTAssertEqual(editor.currentLineNumber(), 2)
        }
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            window.sendEvent(try mouseEvent(type, button: 4))
            XCTAssertEqual(editor.currentLineNumber(), 3)
        }
    }

    private func makeWorkspace() -> (EditorContentViewController, OpenDocumentsStore) {
        _ = NSApplication.shared
        let store = OpenDocumentsStore()
        let controller = NSDocumentController()
        let router = WorkspaceDocumentCoordinator(
            documentOpener: WorkspaceDocumentOpener(documentController: controller, openDocumentsStore: store),
            openDocumentsStore: store, closedDocumentHistory: ClosedDocumentHistory(), documentController: controller
        )
        let workspace = EditorContentViewController(documentStore: store, documentRouter: router)
        workspace.loadViewIfNeeded()
        return (workspace, store)
    }

    private func makeDocument(_ store: OpenDocumentsStore) -> Document {
        Document(sessionIdentifier: UUID(), syntaxOverrideStore: .shared, openDocumentsStore: store)
    }

    private func editor(_ document: Document) -> EditorViewController {
        document.editorViewController(onFileSystemURLsDropped: { _ in })
    }

    private func findTextView(in view: NSView) -> EditorTextView? {
        if let textView = view as? EditorTextView { return textView }
        return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }

    private func keyEvent(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: false, keyCode: code))
    }

    private func mouseEvent(_ type: CGEventType, button: UInt32) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero,
                                           mouseButton: CGMouseButton(rawValue: button)!))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }
}
