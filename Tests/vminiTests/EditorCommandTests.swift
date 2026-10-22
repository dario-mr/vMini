import AppKit
import XCTest
@testable import vmini

@available(macOS 14.0, *)
@MainActor
final class EditorCommandTests: XCTestCase {
    func testMarkdownListEditsPreserveCaretAndSupportUndo() throws {
        let cases: [(Selector, [(String, String)])] = [
            (#selector(NSResponder.insertNewline(_:)), [
                ("- item", "- item\n- "),
                ("* item", "* item\n- "),
                ("+ item", "+ item\n- "),
                ("  9. item", "  9. item\n  10. "),
                ("\t2)\titem", "\t2)\titem\n\t3)\t"),
                ("🙂\n- café 👋", "🙂\n- café 👋\n- "),
                ("```\n- code\n```\n- item", "```\n- code\n```\n- item\n- "),
                ("- ", ""), ("  2. ", "  ")
            ]),
            (#selector(NSResponder.insertTab(_:)), [
                ("- parent\n- ", "- parent\n    - "),
                ("9. parent\n10. ", "9. parent\n    1. "),
                ("  2) parent\n  3) ", "  2) parent\n      1) "),
                ("999. parent\n1000. ", "999. parent\n      1. ")
            ]),
            (#selector(NSResponder.deleteBackward(_:)), [
                ("- parent\n        - ", "- parent\n    - "),
                ("- parent\n    - child\n        - ", "- parent\n    - child\n    - "),
                ("- parent\n    - ", "- parent\n- "),
                ("999. parent\n      1. ", "999. parent\n1. "),
                ("  2) parent\n      1) ", "  2) parent\n  1) "),
                ("- parent\n\t\t- ", "- parent\n\t- "),
                ("- parent\n\t  - ", "- parent\n\t- "),
                ("- parent\n   - ", "- parent\n- "),
                ("- parent\n    -", "- parent\n-"),
                ("- ", ""), ("1. ", ""), ("-", ""), ("2)", "")
            ])
        ]
        _ = NSApplication.shared
        let editor = EditorViewController()
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        defer { window.orderOut(nil) }
        editor.syntaxLanguage = .markdown
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        window.makeFirstResponder(textView)
        let undoManager = try XCTUnwrap(textView.undoManager)
        for (command, examples) in cases {
            for (source, expected) in examples {
                let context = "\(command): \(source.debugDescription)"
                editor.text = source
                textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
                undoManager.removeAllActions()
                var changes = 0
                editor.onTextChanged = { changes += 1 }

                textView.doCommand(by: command)

                XCTAssertEqual(editor.text, expected, context)
                XCTAssertEqual(textView.selectedRange(), NSRange(location: expected.utf16.count, length: 0), context)
                XCTAssertEqual(changes, 1, context)
                undoManager.undo()
                XCTAssertEqual(editor.text, source, context)
                undoManager.redo()
                XCTAssertEqual(editor.text, expected, context)
            }
        }
    }

    func testMarkdownCommandsPreserveNormalEditingAndRespectLanguageChanges() throws {
        let cases: [(Selector, [(SyntaxLanguage, String, String)])] = [
            (#selector(NSResponder.insertNewline(_:)), [
                (.plaintext, "1. item", "1. item\n"),
                (.markdown, "1. item", "1. item\n2. "),
                (.plaintext, "1. item", "1. item\n"),
                (.json, "1. item", "1. item\n"),
                (.markdown, "plain text", "plain text\n"),
                (.markdown, "- - -", "- - -\n"),
                (.markdown, "* * *", "* * *\n"),
                (.markdown, "1.item", "1.item\n"),
                (.markdown, "~~~\n1. item\n~~~\n```\n- item", "~~~\n1. item\n~~~\n```\n- item\n"),
                (.markdown, "9223372036854775807. item", "9223372036854775807. item\n")
            ]),
            (#selector(NSResponder.insertTab(_:)), [
                (.plaintext, "- ", "- \t"),
                (.markdown, "- item", "- item\t"),
                (.markdown, "```\n- ", "```\n- \t"),
                (.markdown, "plain text", "plain text\t")
            ]),
            (#selector(NSResponder.deleteBackward(_:)), [
                (.plaintext, "    - ", "    -"),
                (.markdown, "    - text", "    - tex"),
                (.markdown, "```\n    - ", "```\n    -")
            ])
        ]
        let editor = EditorViewController()
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        for (command, examples) in cases {
            for (language, source, expected) in examples {
                editor.syntaxLanguage = language
                editor.text = source
                textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
                textView.doCommand(by: command)
                XCTAssertEqual(editor.text, expected, "\(command), \(language): \(source.debugDescription)")
            }
        }
        editor.syntaxLanguage = .markdown
        for (command, source, selection, expected) in [
            (#selector(NSResponder.insertNewline(_:)), "- first\n- second", NSRange(location: 2, length: 9), "- \necond"),
            (#selector(NSResponder.insertTab(_:)), "- ", NSRange(location: 0, length: 2), "\t- "),
            (#selector(NSResponder.deleteBackward(_:)), "    - ", NSRange(location: 4, length: 2), "    ")
        ] {
            editor.text = source
            textView.setSelectedRange(selection)
            textView.doCommand(by: command)
            XCTAssertEqual(editor.text, expected, "\(command): \(source.debugDescription)")
        }
    }

    func testMarkdownReturnReplacesSelectionAndPreservesFollowingText() throws {
        let editor = EditorViewController()
        editor.syntaxLanguage = .markdown
        editor.text = "3. first selected last\nnext line"
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        textView.setSelectedRange((editor.text as NSString).range(of: "selected "))

        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(editor.text, "3. first \n4. last\nnext line")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: "3. first \n4. ".utf16.count, length: 0))
    }

    func testIndentedOrderedListContinuesNumberingAtItsNewLevel() throws {
        let editor = EditorViewController()
        editor.syntaxLanguage = .markdown
        editor.text = "1. parent"
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        textView.setSelectedRange(NSRange(location: editor.text.utf16.count, length: 0))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(editor.text, "1. parent\n        1. ")
        textView.insertText("child", replacementRange: textView.selectedRange())
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(editor.text, "1. parent\n        1. child\n        2. ")
    }

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

    func testFormatJSONFormatsDocumentOrSelection() throws {
        for (source, selectedText, expected) in [
            ("{\"name\":\"vmini\",\"items\":[1,true]}", "", """
            {
              "name": "vmini",
              "items": [
                1,
                true
              ]
            }
            """),
            ("prefix {\"name\":\"vmini\",\"enabled\":true} suffix", "{\"name\":\"vmini\",\"enabled\":true}", """
            prefix {
              "name": "vmini",
              "enabled": true
            } suffix
            """)
        ] {
            let editor = EditorViewController()
            editor.text = source
            let textView = try XCTUnwrap(findTextView(in: editor.view))
            textView.setSelectedRange(selectedText.isEmpty ? NSRange(location: 0, length: 0) : (source as NSString).range(of: selectedText))
            editor.formatJSONSelectionOrDocument()
            XCTAssertEqual(editor.text, expected, source)
        }
    }

    func testFormatJSONReportsInvalidJSONWithoutChangingText() {
        let viewController = EditorViewController()
        _ = viewController.view
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
        _ = viewController.view
        viewController.text = "{\"name\": }"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        viewController.formatJSONSelectionOrDocument()

        XCTAssertEqual(viewController.formattingErrorMessage, "Couldn’t Format JSON: Unexpected character '}' at character 10.")

        textView.insertText(" ", replacementRange: NSRange(location: textView.selectedRange().location, length: 0))

        XCTAssertNil(viewController.formattingErrorMessage)
    }

    func testInlineFormattingErrorCanBeDismissedWithoutEditing() {
        let viewController = EditorViewController()
        _ = viewController.view
        viewController.text = "{\"name\": }"

        viewController.formatJSONSelectionOrDocument()
        XCTAssertNotNil(viewController.formattingErrorMessage)

        viewController.dismissFormattingErrorBanner()

        XCTAssertNil(viewController.formattingErrorMessage)
    }

    func testDeleteCurrentLineRemovesCaretOrSelectedLines() throws {
        for (source, selection, expected, caret) in [
            ("alpha\nbeta\ngamma", NSRange(location: 7, length: 0), "alpha\ngamma", 6),
            ("alpha\nbeta\ngamma\ndelta", NSRange(location: 2, length: 8), "gamma\ndelta", 0)
        ] {
            let editor = EditorViewController()
            editor.text = source
            let textView = try XCTUnwrap(findTextView(in: editor.view))
            textView.setSelectedRange(selection)
            editor.deleteCurrentLine()
            XCTAssertEqual(editor.text, expected, source)
            XCTAssertEqual(textView.selectedRange(), NSRange(location: caret, length: 0), source)
        }
    }

    func testTabIndentsSelectedLinesWithoutReplacingSelection() throws {
        for (source, selectedText, expected, expectedSelection) in [
            ("prefix selected suffix", "selected", "\tprefix selected suffix", NSRange(location: 8, length: 8)),
            ("alpha\nbeta\ngamma", "beta\ngamma", "alpha\n\tbeta\n\tgamma", NSRange(location: 7, length: 11))
        ] {
            let editor = EditorViewController()
            editor.text = source
            let textView = try XCTUnwrap(findTextView(in: editor.view))
            textView.setSelectedRange((source as NSString).range(of: selectedText))
            textView.insertTab(nil)
            XCTAssertEqual(editor.text, expected, source)
            XCTAssertEqual(textView.selectedRange(), expectedSelection, source)
        }
    }

    func testTypingDelimitersWrapsSelectionAndSupportsUndo() throws {
        for (opening, closing) in [("`", "`"), ("'", "'"), ("\"", "\""),
                                   ("(", ")"), ("[", "]"), ("{", "}"),
                                   ("*", "*"), ("_", "_"), ("~", "~")] {
            let editor = EditorViewController()
            _ = editor.view
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

    func testEscapeCollapsesSelectionAndPreservesExistingCaret() {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.string = "hello world"
        for (selection, caret) in [(NSRange(location: 2, length: 5), 7), (NSRange(location: 4, length: 0), 4)] {
            textView.setSelectedRange(selection)
            textView.cancelOperation(nil)
            XCTAssertEqual(textView.selectedRange(), NSRange(location: caret, length: 0))
        }
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
