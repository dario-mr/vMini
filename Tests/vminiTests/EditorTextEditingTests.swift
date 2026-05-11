import XCTest
@testable import vmini

final class EditorTextEditingTests: XCTestCase {
    func testCurrentCursorPositionUsesOneBasedLineAndColumn() {
        let text = "alpha\nbeta\ngamma" as NSString
        let cursor = EditorTextEditing.currentCursorPosition(in: text, selectedRange: NSRange(location: 8, length: 0))

        XCTAssertEqual(cursor.line, 2)
        XCTAssertEqual(cursor.column, 3)
    }

    func testCharacterLocationForLineNumberClampsToDocumentEnd() {
        let text = "alpha\nbeta" as NSString

        XCTAssertEqual(EditorTextEditing.characterLocation(forLineNumber: 1, in: text), 0)
        XCTAssertEqual(EditorTextEditing.characterLocation(forLineNumber: 2, in: text), 6)
        XCTAssertEqual(EditorTextEditing.characterLocation(forLineNumber: 99, in: text), text.length)
    }

    func testToggleLineCommentUsesSlashSlashForMarkdown() throws {
        let text = "one\ntwo\nthree" as NSString
        let selection = NSRange(location: 4, length: 3)

        let edit = try XCTUnwrap(
            EditorTextEditing.toggleLineComment(in: text, selectedRange: selection, syntaxLanguage: .markdown)
        )

        XCTAssertEqual(edit.replacementRange, NSRange(location: 4, length: 4))
        XCTAssertEqual(edit.replacementText, "//two\n")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 6, length: 3))
    }

    func testToggleLineCommentUsesHashForBash() throws {
        let text = "echo hi" as NSString

        let edit = try XCTUnwrap(
            EditorTextEditing.toggleLineComment(in: text, selectedRange: NSRange(location: 0, length: 0), syntaxLanguage: .bash)
        )

        XCTAssertEqual(edit.replacementRange, NSRange(location: 0, length: 7))
        XCTAssertEqual(edit.replacementText, "#echo hi")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 1, length: 0))
    }

    func testDuplicateSelectedLinesAtEndOfFileAddsLeadingNewline() {
        let text = "one\ntwo" as NSString
        let edit = EditorTextEditing.duplicateSelectedLines(in: text, selectedRange: NSRange(location: 4, length: 0))

        XCTAssertEqual(edit.replacementRange, NSRange(location: 7, length: 0))
        XCTAssertEqual(edit.replacementText, "\ntwo")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 8, length: 0))
    }

    func testMoveSelectedLinesUpReordersAdjacentBlocks() throws {
        let text = "one\ntwo\nthree\n" as NSString
        let edit = try XCTUnwrap(
            EditorTextEditing.moveSelectedLines(in: text, selectedRange: NSRange(location: 4, length: 0), direction: .up)
        )

        XCTAssertEqual(edit.replacementRange, NSRange(location: 0, length: 8))
        XCTAssertEqual(edit.replacementText, "two\none\n")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 0, length: 0))
    }

    func testMoveSelectedLinesDownReordersAdjacentBlocks() throws {
        let text = "one\ntwo\nthree\n" as NSString
        let edit = try XCTUnwrap(
            EditorTextEditing.moveSelectedLines(in: text, selectedRange: NSRange(location: 4, length: 0), direction: .down)
        )

        XCTAssertEqual(edit.replacementRange, NSRange(location: 4, length: 10))
        XCTAssertEqual(edit.replacementText, "three\ntwo\n")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 10, length: 0))
    }

    func testMoveSelectedLinesReturnsNilAtDocumentBounds() {
        let text = "one\ntwo" as NSString

        XCTAssertNil(EditorTextEditing.moveSelectedLines(in: text, selectedRange: NSRange(location: 0, length: 0), direction: .up))
        XCTAssertNil(EditorTextEditing.moveSelectedLines(in: text, selectedRange: NSRange(location: 4, length: 0), direction: .down))
    }
}
