import XCTest
@testable import vmini

@MainActor
private final class LineNumberRulerStorageDelegate: NSObject, @preconcurrency NSTextStorageDelegate {
    private let ruler: LineNumberRulerView

    init(ruler: LineNumberRulerView) {
        self.ruler = ruler
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        ruler.noteTextStorageDidEdit(textStorage, editedRange: editedRange, changeInLength: delta)
    }
}

@MainActor
private final class UndoableTextView: NSTextView {
    private let testUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        testUndoManager
    }
}

final class EditorTextEditingTests: XCTestCase {
    func testCurrentCursorPositionUsesOneBasedLineAndColumn() {
        let text = "alpha\nbeta\ngamma" as NSString
        let cursor = EditorTextEditing.currentCursorPosition(in: text, selectedRange: NSRange(location: 8, length: 0))

        XCTAssertEqual(cursor.line, 2)
        XCTAssertEqual(cursor.column, 3)
    }

    @MainActor
    func testLineNumberRulerCursorPositionUsesCachedLineStarts() {
        let textView = NSTextView()
        textView.string = "alpha\nbeta\ngamma"
        let ruler = LineNumberRulerView(textView: textView)
        ruler.resetLineCache()

        textView.setSelectedRange(NSRange(location: 8, length: 0))
        let cursor = ruler.currentCursorPosition()

        XCTAssertEqual(cursor.line, 2)
        XCTAssertEqual(cursor.column, 3)
    }

    @MainActor
    func testLineNumberRulerUpdatesCacheAfterDeletingLine() {
        let textView = NSTextView()
        textView.string = "one\ntwo\nthree"
        let ruler = LineNumberRulerView(textView: textView)
        ruler.resetLineCache()

        let storage = textView.textStorage!
        storage.replaceCharacters(in: NSRange(location: 4, length: 4), with: "")
        ruler.noteTextStorageDidEdit(
            storage,
            editedRange: NSRange(location: 4, length: 0),
            changeInLength: -4
        )
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        XCTAssertEqual(ruler.currentCursorPosition().line, 2)
    }

    @MainActor
    func testLineNumberRulerClearsMarkerWhenBackspaceRestoresSavedText() {
        let textView = UndoableTextView()
        let ruler = LineNumberRulerView(textView: textView)
        ruler.resetLineCache()
        let storage = textView.textStorage!
        let delegate = LineNumberRulerStorageDelegate(ruler: ruler)
        storage.delegate = delegate

        textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 1))

        textView.deleteBackward(nil)
        XCTAssertEqual(textView.string, "")
        XCTAssertFalse(ruler.hasUnsavedChanges(onLine: 1))
    }

    @MainActor
    func testUndoAndRedoUpdateLineNumberRulerMarker() throws {
        let textView = UndoableTextView()
        let ruler = LineNumberRulerView(textView: textView)
        ruler.resetLineCache()
        let storage = try XCTUnwrap(textView.textStorage)
        let delegate = LineNumberRulerStorageDelegate(ruler: ruler)
        storage.delegate = delegate

        textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(textView.string, "a")
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 1))
        XCTAssertTrue(try XCTUnwrap(textView.undoManager).canUndo)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "")
        XCTAssertFalse(ruler.hasUnsavedChanges(onLine: 1))

        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "a")
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 1))
    }

    @MainActor
    func testLineNumberRulerRecalculatesMarkersAcrossLineChangesAndReverts() {
        let textView = NSTextView()
        textView.string = "one\ntwo\nthree"
        let ruler = LineNumberRulerView(textView: textView)
        ruler.resetLineCache()
        let storage = textView.textStorage!

        storage.replaceCharacters(in: NSRange(location: 4, length: 3), with: "TWO\nnew")
        ruler.noteTextStorageDidEdit(storage, editedRange: NSRange(location: 4, length: 7), changeInLength: 4)
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 2))
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 3))
        XCTAssertFalse(ruler.hasUnsavedChanges(onLine: 4))

        storage.replaceCharacters(in: NSRange(location: 4, length: 7), with: "two")
        ruler.noteTextStorageDidEdit(storage, editedRange: NSRange(location: 4, length: 3), changeInLength: -4)
        XCTAssertFalse(ruler.hasUnsavedChanges(onLine: 2))
        XCTAssertFalse(ruler.hasUnsavedChanges(onLine: 3))
    }

    @MainActor
    func testLineNumberRulerClearsOnlyTheLineRevertedWhileOtherEditsRemain() {
        let textView = NSTextView()
        textView.string = "one\ntwo\nthree"
        let ruler = LineNumberRulerView(textView: textView)
        ruler.resetLineCache()
        let storage = textView.textStorage!

        storage.replaceCharacters(in: NSRange(location: 4, length: 3), with: "TWO")
        ruler.noteTextStorageDidEdit(storage, editedRange: NSRange(location: 4, length: 3), changeInLength: 0)
        storage.replaceCharacters(in: NSRange(location: 8, length: 5), with: "THREE")
        ruler.noteTextStorageDidEdit(storage, editedRange: NSRange(location: 8, length: 5), changeInLength: 0)
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 2))
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 3))

        storage.replaceCharacters(in: NSRange(location: 4, length: 3), with: "two")
        ruler.noteTextStorageDidEdit(storage, editedRange: NSRange(location: 4, length: 3), changeInLength: 0)
        XCTAssertFalse(ruler.hasUnsavedChanges(onLine: 2))
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 3))
    }

    @MainActor
    func testLineNumberRulerMarkerClearsWhenEditedTextIsSaved() {
        let textView = NSTextView()
        textView.string = "saved"
        let ruler = LineNumberRulerView(textView: textView)
        ruler.resetLineCache()
        let storage = textView.textStorage!

        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " text")
        ruler.noteTextStorageDidEdit(storage, editedRange: NSRange(location: 5, length: 5), changeInLength: 5)
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 1))

        ruler.markChangesSaved()
        XCTAssertFalse(ruler.hasUnsavedChanges(onLine: 1))

        storage.replaceCharacters(in: NSRange(location: 5, length: 5), with: "")
        ruler.noteTextStorageDidEdit(storage, editedRange: NSRange(location: 5, length: 0), changeInLength: -5)
        XCTAssertTrue(ruler.hasUnsavedChanges(onLine: 1))
    }

    @MainActor
    func testEditedLineIndexesHandlesEmptyTextLineChangesAndReverts() {
        XCTAssertEqual(LineNumberRulerView.editedLineIndexes(currentText: "a", savedText: ""), [0])
        XCTAssertEqual(LineNumberRulerView.editedLineIndexes(currentText: "", savedText: ""), [])
        XCTAssertEqual(LineNumberRulerView.editedLineIndexes(currentText: "one\nTWO\nthree", savedText: "one\ntwo\nthree"), [1])
        XCTAssertEqual(LineNumberRulerView.editedLineIndexes(currentText: "one\nthree", savedText: "one\ntwo\nthree"), [1])
        XCTAssertEqual(LineNumberRulerView.editedLineIndexes(currentText: "one\ntwo\nthree", savedText: "one\nthree"), [1])
        XCTAssertEqual(LineNumberRulerView.editedLineIndexes(currentText: "line\n", savedText: "line"), [1])
        XCTAssertEqual(LineNumberRulerView.editedLineIndexes(currentText: "line", savedText: "line\n"), [0])
        XCTAssertEqual(LineNumberRulerView.editedLineIndexes(currentText: "a", savedText: "a"), [])
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

    func testBracketMatchingFindsPairAfterOpeningBracket() throws {
        let text = "call(foo[bar])" as NSString

        let match = try XCTUnwrap(
            EditorBracketMatching.match(
                near: NSRange(location: 5, length: 0),
                in: text
            )
        )

        XCTAssertEqual(match.range, NSRange(location: 4, length: 1))
        XCTAssertEqual(match.matchingRange, NSRange(location: 13, length: 1))
    }

    func testBracketMatchingFindsPairBeforeClosingBracket() throws {
        let text = "{ alpha: [beta] }" as NSString

        let match = try XCTUnwrap(
            EditorBracketMatching.match(
                near: NSRange(location: 14, length: 0),
                in: text
            )
        )

        XCTAssertEqual(match.range, NSRange(location: 14, length: 1))
        XCTAssertEqual(match.matchingRange, NSRange(location: 9, length: 1))
    }

    func testBracketMatchingHonorsNestedPairs() throws {
        let text = "([{}])" as NSString

        let match = try XCTUnwrap(
            EditorBracketMatching.match(
                near: NSRange(location: 1, length: 0),
                in: text
            )
        )

        XCTAssertEqual(match.range, NSRange(location: 0, length: 1))
        XCTAssertEqual(match.matchingRange, NSRange(location: 5, length: 1))
    }

    func testBracketMatchingReturnsNilWhenNoAdjacentBracketExists() {
        let text = "plain text" as NSString

        XCTAssertNil(
            EditorBracketMatching.match(
                near: NSRange(location: 3, length: 0),
                in: text
            )
        )
    }
}
