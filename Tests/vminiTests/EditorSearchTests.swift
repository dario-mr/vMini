import AppKit
import XCTest
@testable import vmini

@MainActor
final class EditorSearchTests: XCTestCase {
    func testMatching() {
        for (text, query, expected) in [
            ("a.b A.B axb a.b", "a.b", [0, 4, 12].map { NSRange(location: $0, length: 3) }),
            ("aaaaa", "aa", [0, 2].map { NSRange(location: $0, length: 2) }),
            ("😀 A\nb 😀 a\nB", "a\nb", [3, 10].map { NSRange(location: $0, length: 3) }),
            ("😀😀", "😀", [0, 2].map { NSRange(location: $0, length: 2) }),
            ("a a", " ", [NSRange(location: 1, length: 1)]),
            ("anything", "", []), ("", "a", []),
        ] {
            XCTAssertEqual(EditorSearchController.matchingRanges(in: text, query: query), expected, "Query: \(query)")
        }
    }

    func testKeyboardShortcuts() throws {
        for (key, code, modifiers, action) in [
            ("f", UInt16(3), NSEvent.ModifierFlags.command, EditorSearchAction.find),
            ("r", 15, .command, .replace),
            ("", 99, .function, .next), ("", 120, .function, .previous), ("", 53, [], .close),
        ] {
            XCTAssertEqual(EditorSearchAction.action(for: try event(key, code: code, modifiers: modifiers)), action)
        }
        XCTAssertNil(EditorSearchAction.action(for: try event("f", code: 3, modifiers: [.command, .shift])))
        XCTAssertNil(EditorSearchAction.action(for: try event("", code: 99, modifiers: [.option, .function])))
    }

    func testFindSessionSeedsSelectionWrapsAndRestoresFocus() throws {
        let (editor, textView, window) = try makeEditor("foo bar FOO foo")
        defer { window.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        editor.performSearchAction(.find)
        let search = editor.searchController
        XCTAssertEqual(search.panel.searchField.stringValue, "foo")
        XCTAssertTrue(window.firstResponder === search.panel.searchField.currentEditor())
        for location in [8, 12, 0] {
            editor.performSearchAction(.next)
            XCTAssertEqual(textView.selectedRange().location, location)
        }
        editor.performSearchAction(.previous)
        XCTAssertEqual(textView.selectedRange().location, 12)
        XCTAssertEqual(search.panel.countLabel.stringValue, "3 of 3")
        try XCTUnwrap(window.firstResponder as? NSTextView).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertFalse(search.isVisible)
        XCTAssertTrue(window.firstResponder === textView)

        textView.setSelectedRange(NSRange(location: 4, length: 3))
        editor.performSearchAction(.next)
        XCTAssertEqual(search.panel.searchField.stringValue, "foo")
        XCTAssertEqual(textView.selectedRange().location, 8)
        textView.cancelOperation(nil)
        XCTAssertFalse(search.isVisible)
    }

    func testHighlightsFollowQueryEditsAndUndo() async throws {
        let (editor, textView, window) = try makeEditor("foo FOO")
        defer { window.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        editor.performSearchAction(.find)
        let search = editor.searchController
        let color = background(textView, at: 4)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNotNil(color)
        XCTAssertEqual(background(textView, at: 4), color)
        XCTAssertNil(textView.textStorage?.attribute(.backgroundColor, at: 4, effectiveRange: nil))

        textView.insertText("prefix ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(search.matches, [7, 11].map { NSRange(location: $0, length: 3) })
        XCTAssertNil(background(textView, at: 0))
        XCTAssertNotNil(background(textView, at: 11))
        textView.undoManager?.undo()
        XCTAssertEqual(editor.text, "foo FOO")
        XCTAssertEqual(search.matches.count, 2)
        for query in ["missing", ""] {
            setQuery(query, in: search)
            XCTAssertTrue(search.matches.isEmpty)
            XCTAssertNil(background(textView, at: 4))
            XCTAssertFalse(search.panel.nextButton.isEnabled)
            XCTAssertFalse(search.panel.replaceAllButton.isEnabled)
        }
        setQuery("foo", in: search)
        editor.text = "x"
        XCTAssertTrue(search.matches.isEmpty)
        XCTAssertNil(background(textView, at: 0))
    }

    func testReplaceAndReplaceAllAreLiteralAndUndoable() throws {
        let original = "😀foo FOO foo"
        let (editor, textView, window) = try makeEditor(original)
        defer { window.orderOut(nil) }
        editor.performSearchAction(.replace)
        let search = editor.searchController
        setQuery("foo", in: search)
        search.panel.replacementField.stringValue = "longer"
        search.panel.replaceButton.performClick(nil)
        XCTAssertEqual(editor.text, "😀longer FOO foo")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 3))
        textView.undoManager?.undo()
        XCTAssertEqual(editor.text, original)

        search.panel.replacementField.stringValue = "foo$1\\"
        var changed = 0
        editor.onTextChanged = { changed += 1 }
        search.panel.replaceAllButton.performClick(nil)
        let replaced = "😀foo$1\\ foo$1\\ foo$1\\"
        XCTAssertEqual(editor.text, replaced)
        XCTAssertEqual(changed, 1)
        textView.undoManager?.undo()
        XCTAssertEqual(editor.text, original)
        textView.undoManager?.redo()
        XCTAssertEqual(editor.text, replaced)
        textView.undoManager?.undo()
        search.panel.replacementField.stringValue = ""
        search.panel.replaceAllButton.performClick(nil)
        XCTAssertEqual(editor.text, "😀  ")
        XCTAssertTrue(search.matches.isEmpty)
    }

    func testFieldFocusCyclesAndTextStaysVerticallyCentered() throws {
        let (editor, _, window) = try makeEditor("foo")
        defer { window.orderOut(nil) }
        editor.performSearchAction(.replace)
        let panel = editor.searchController.panel
        setQuery("foo", in: editor.searchController)
        panel.replacementField.stringValue = "bar"
        editor.view.layoutSubtreeIfNeeded()
        for field in [panel.replacementField, panel.searchField] {
            try XCTUnwrap(window.firstResponder as? NSTextView).doCommand(by: #selector(NSResponder.insertTab(_:)))
            XCTAssertTrue(window.firstResponder === field.currentEditor())
            let textRect = try XCTUnwrap(field.cell).drawingRect(forBounds: field.bounds)
            XCTAssertEqual(textRect.midY, field.bounds.midY, accuracy: 0.5)
            let fieldEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            let layout = try XCTUnwrap(fieldEditor.layoutManager)
            layout.ensureLayout(for: try XCTUnwrap(fieldEditor.textContainer))
            let line = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
                .offsetBy(dx: fieldEditor.textContainerOrigin.x, dy: fieldEditor.textContainerOrigin.y)
            XCTAssertEqual(fieldEditor.convert(line, to: field).midY, field.bounds.midY, accuracy: 0.5)
        }
        for field in [panel.replacementField, panel.searchField] {
            try XCTUnwrap(window.firstResponder as? NSTextView).doCommand(by: #selector(NSResponder.insertBacktab(_:)))
            XCTAssertTrue(window.firstResponder === field.currentEditor())
        }
        XCTAssertEqual(panel.searchField.stringValue, "foo")
        XCTAssertEqual(panel.replacementField.stringValue, "bar")
        XCTAssertEqual(editor.text, "foo")
        editor.performSearchAction(.find)
        for command in [#selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:))] {
            try XCTUnwrap(window.firstResponder as? NSTextView).doCommand(by: command)
            XCTAssertTrue(window.firstResponder === panel.searchField.currentEditor())
        }
    }

    private func makeEditor(_ text: String) throws -> (EditorViewController, NSTextView, NSWindow) {
        _ = NSApplication.shared
        let editor = EditorViewController()
        _ = editor.view
        editor.text = text
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let host = try XCTUnwrap(window.contentView)
        host.addSubview(editor.view)
        NSLayoutConstraint.activate([
            editor.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            editor.view.topAnchor.constraint(equalTo: host.topAnchor),
            editor.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        host.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(editor.textStorage?.layoutManagers.first?.textContainers.first?.textView)
        window.makeFirstResponder(textView)
        return (editor, textView, window)
    }

    private func setQuery(_ query: String, in search: EditorSearchController) {
        search.panel.searchField.stringValue = query
        search.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search.panel.searchField))
    }

    private func background(_ textView: NSTextView, at location: Int) -> NSColor? {
        textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: location, effectiveRange: nil) as? NSColor
    }

    private func event(_ key: String, code: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                       windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                                       isARepeat: false, keyCode: code))
    }
}
