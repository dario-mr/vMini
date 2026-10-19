import AppKit
import XCTest
@testable import vmini

@available(macOS 14.0, *)
@MainActor
final class EditorCommandTests: XCTestCase {
    func testCommandShiftZRedoesNativeUndo() throws {
        _ = NSApplication.shared
        let editor = EditorViewController()
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        defer { window.orderOut(nil) }
        editor.text = "hello"
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        window.makeFirstResponder(textView)
        textView.insertText(" world", replacementRange: NSRange(location: 5, length: 0))
        XCTAssertEqual(editor.text, "hello world")
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.undo()
        XCTAssertEqual(editor.text, "hello")

        let redoEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "Z",
            charactersIgnoringModifiers: "Z", isARepeat: false, keyCode: 6
        ))
        XCTAssertTrue(window.performKeyEquivalent(with: redoEvent))
        XCTAssertEqual(editor.text, "hello world")
        XCTAssertFalse(undoManager.canRedo)
        XCTAssertTrue(window.performKeyEquivalent(with: redoEvent))
        XCTAssertEqual(editor.text, "hello world")
    }

    func testFormatJSONFormatsWholeDocumentWhenNothingIsSelected() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "{\"name\":\"vmini\",\"items\":[1,true]}"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        viewController.formatJSONSelectionOrDocument()

        XCTAssertEqual(
            viewController.text,
            """
            {
              "name": "vmini",
              "items": [
                1,
                true
              ]
            }
            """
        )
    }

    func testFormatJSONFormatsOnlySelectedText() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "prefix {\"name\":\"vmini\",\"enabled\":true} suffix"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        let nsText = viewController.text as NSString
        let selectedRange = nsText.range(of: "{\"name\":\"vmini\",\"enabled\":true}")
        textView.setSelectedRange(selectedRange)

        viewController.formatJSONSelectionOrDocument()

        XCTAssertEqual(
            viewController.text,
            """
            prefix {
              "name": "vmini",
              "enabled": true
            } suffix
            """
        )
    }

    func testFormatJSONReportsInvalidJSONWithoutChangingText() {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "{\"name\": }"

        var receivedError: (String, String)?
        viewController.onJSONFormattingError = { title, message in
            receivedError = (title, message)
        }

        viewController.formatJSONSelectionOrDocument()

        XCTAssertEqual(viewController.text, "{\"name\": }")
        XCTAssertEqual(receivedError?.0, "Couldn’t Format JSON")
        XCTAssertTrue(receivedError?.1.contains("not valid JSON") == true)
    }

    func testInlineFormattingErrorClearsAfterNextEdit() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "{\"name\": }"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        viewController.formatJSONSelectionOrDocument()

        XCTAssertEqual(viewController.formattingErrorMessage, "Couldn’t Format JSON: Unexpected character '}' at character 10.")

        textView.insertText(" ", replacementRange: NSRange(location: textView.selectedRange().location, length: 0))

        XCTAssertNil(viewController.formattingErrorMessage)
    }

    func testInlineFormattingErrorCanBeDismissedWithoutEditing() {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "{\"name\": }"

        viewController.formatJSONSelectionOrDocument()
        XCTAssertNotNil(viewController.formattingErrorMessage)

        viewController.dismissFormattingErrorBanner()

        XCTAssertNil(viewController.formattingErrorMessage)
    }

    func testDeleteCurrentLineRemovesLineAtCaret() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "alpha\nbeta\ngamma"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 7, length: 0))

        viewController.deleteCurrentLine()

        XCTAssertEqual(viewController.text, "alpha\ngamma")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testDeleteCurrentLineRemovesSelectedLines() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "alpha\nbeta\ngamma\ndelta"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 2, length: 8))

        viewController.deleteCurrentLine()

        XCTAssertEqual(viewController.text, "gamma\ndelta")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testTabIndentsSingleLineSelectionInsteadOfReplacingIt() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "prefix selected suffix"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        let selectedRange = (viewController.text as NSString).range(of: "selected")
        textView.setSelectedRange(selectedRange)

        textView.insertTab(nil)

        XCTAssertEqual(viewController.text, "\tprefix selected suffix")
        XCTAssertEqual(
            textView.selectedRange(),
            NSRange(location: selectedRange.location + 1, length: selectedRange.length)
        )
    }

    func testTabIndentsEveryLineInMultilineSelectionInsteadOfReplacingIt() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.text = "alpha\nbeta\ngamma"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        let selectedRange = (viewController.text as NSString).range(of: "beta\ngamma")
        textView.setSelectedRange(selectedRange)

        textView.insertTab(nil)

        XCTAssertEqual(viewController.text, "alpha\n\tbeta\n\tgamma")
        XCTAssertEqual(
            textView.selectedRange(),
            NSRange(location: selectedRange.location + 1, length: selectedRange.length + 1)
        )
    }

    func testTypingDelimitersWrapsSelectionAndSupportsUndo() throws {
        for (opening, closing) in [("`", "`"), ("'", "'"), ("\"", "\""),
                                   ("(", ")"), ("[", "]"), ("{", "}"),
                                   ("*", "*"), ("_", "_"), ("~", "~")] {
            let editor = EditorViewController()
            editor.loadViewIfNeeded()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentViewController = editor
            defer { window.orderOut(nil) }
            let original = "prefix 😀one\ntwo suffix"
            editor.text = original
            let textView = try XCTUnwrap(findTextView(in: editor.view))
            let selection = (original as NSString).range(of: "😀one\ntwo")
            textView.setSelectedRange(selection)
            var changes = 0
            editor.onTextChanged = { changes += 1 }

            textView.insertText(opening, replacementRange: NSRange(location: NSNotFound, length: 0))

            let wrapped = "prefix \(opening)😀one\ntwo\(closing) suffix"
            XCTAssertEqual(editor.text, wrapped)
            XCTAssertEqual(textView.selectedRange(), NSRange(location: selection.location + 1, length: selection.length))
            XCTAssertEqual(changes, 1)
            let undoManager = try XCTUnwrap(textView.undoManager)
            undoManager.undo()
            XCTAssertEqual(editor.text, original)
            undoManager.redo()
            XCTAssertEqual(editor.text, wrapped)
        }
    }

    func testTypingDelimitersWithoutSelectionInsertsOneCharacter() {
        for delimiter in ["`", "'", "\"", "(", "[", "{", "*", "_", "~"] {
            let textView = EditorTextView()
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.string = "ab"
            textView.setSelectedRange(NSRange(location: 1, length: 0))

            textView.insertText(delimiter, replacementRange: NSRange(location: NSNotFound, length: 0))

            XCTAssertEqual(textView.string, "a\(delimiter)b")
            XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        }
    }

    func testExplicitReplacementAndOrdinaryTypingStillReplaceSelection() {
        for (input, range) in [("'", NSRange(location: 0, length: 3)),
                               ("(", NSRange(location: 0, length: 3)),
                               ("*", NSRange(location: 0, length: 3)),
                               (")", NSRange(location: NSNotFound, length: 0)),
                               ("]", NSRange(location: NSNotFound, length: 0)),
                               ("}", NSRange(location: NSNotFound, length: 0)),
                               ("x", NSRange(location: NSNotFound, length: 0)),
                               ("''", NSRange(location: NSNotFound, length: 0))] {
            let textView = EditorTextView()
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.string = "abc"
            textView.setSelectedRange(NSRange(location: 0, length: 3))

            textView.insertText(input, replacementRange: range)

            XCTAssertEqual(textView.string, input)
        }
    }

    func testEscapeCollapsesActiveSelectionToInsertionPoint() {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.string = "hello world"
        textView.setSelectedRange(NSRange(location: 2, length: 5))

        textView.cancelOperation(nil)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 0))
    }

    func testEscapeWithoutSelectionPreservesInsertionPoint() {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.string = "hello world"
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.cancelOperation(nil)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testHomeAndEndMoveCaretToDocumentBounds() {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.string = "alpha\nbeta\ngamma"
        textView.setSelectedRange(NSRange(location: 8, length: 0))

        textView.scrollToBeginningOfDocument(nil)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))

        textView.scrollToEndOfDocument(nil)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))
    }

    func testPageDownAndUpMoveCaretBetweenVisiblePages() {
        let lines = (0..<200).map { "line \($0)" }.joined(separator: "\n")
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.string = lines
        textView.layoutSubtreeIfNeeded()
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        textView.pageDown(nil)
        let afterPageDown = textView.selectedRange().location
        XCTAssertGreaterThan(afterPageDown, 0)

        textView.pageUp(nil)
        XCTAssertLessThan(textView.selectedRange().location, afterPageDown)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }
}
