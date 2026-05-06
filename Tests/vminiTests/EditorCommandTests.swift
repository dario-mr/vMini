import AppKit
import XCTest
@testable import vmini

@MainActor
final class EditorCommandTests: XCTestCase {
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
}
