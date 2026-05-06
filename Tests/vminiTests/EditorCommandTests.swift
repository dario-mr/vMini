import AppKit
import XCTest
@testable import vmini

@MainActor
final class EditorCommandTests: XCTestCase {
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

    func testEscapeCollapsesActiveSelectionToInsertionPoint() {
        let textView = FileDropTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.string = "hello world"
        textView.setSelectedRange(NSRange(location: 2, length: 5))

        textView.cancelOperation(nil)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 0))
    }

    func testEscapeWithoutSelectionPreservesInsertionPoint() {
        let textView = FileDropTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.string = "hello world"
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.cancelOperation(nil)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testHomeAndEndMoveCaretToDocumentBounds() {
        let textView = FileDropTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.string = "alpha\nbeta\ngamma"
        textView.setSelectedRange(NSRange(location: 8, length: 0))

        textView.scrollToBeginningOfDocument(nil)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))

        textView.scrollToEndOfDocument(nil)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))
    }

    func testPageDownAndUpMoveCaretBetweenVisiblePages() {
        let lines = (0..<200).map { "line \($0)" }.joined(separator: "\n")
        let textView = FileDropTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
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
