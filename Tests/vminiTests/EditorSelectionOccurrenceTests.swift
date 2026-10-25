import AppKit
import XCTest
@testable import vmini

@MainActor
final class EditorSelectionOccurrenceTests: XCTestCase {
    func testMatchingIsLiteralCaseSensitiveAndIncludesSubstrings() {
        let text = "a.b A.B a.b a.bigger"
        XCTAssertEqual(EditorSelectionOccurrenceController.matchingRanges(
            in: text, selection: NSRange(location: 0, length: 3)
        ), [0, 8, 12].map { NSRange(location: $0, length: 3) })
    }

    func testMatchingUsesUTF16RangesAndExactUnicode() {
        let text = "😀 é e\u{301} 😀 é" as NSString
        XCTAssertEqual(EditorSelectionOccurrenceController.matchingRanges(
            in: text as String, selection: NSRange(location: 0, length: 2)
        ), [text.range(of: "😀"), text.range(of: "😀", options: .backwards)])
        XCTAssertEqual(EditorSelectionOccurrenceController.matchingRanges(
            in: text as String, selection: text.range(of: "é", options: .literal)
        ), [text.range(of: "é", options: .literal), text.range(of: "é", options: [.literal, .backwards])])
    }

    func testMatchingSupportsMultilineSelections() {
        XCTAssertEqual(EditorSelectionOccurrenceController.matchingRanges(
            in: "foo\nbar foo\nbar", selection: NSRange(location: 0, length: 7)
        ), [NSRange(location: 0, length: 7), NSRange(location: 8, length: 7)])
    }

    func testEmptyWhitespaceAndInvalidSelectionsHaveNoMatches() {
        for selection in [
            NSRange(location: 0, length: 0), NSRange(location: 0, length: 3),
            NSRange(location: NSNotFound, length: 1), NSRange(location: -1, length: 1),
            NSRange(location: 4, length: 10), NSRange(location: 0, length: Int.max),
        ] {
            XCTAssertTrue(EditorSelectionOccurrenceController.matchingRanges(in: " \t\nword", selection: selection).isEmpty)
        }
    }

    func testMatchingFindsOccurrencesThroughoutLargeDocument() {
        let text = String(repeating: "word other\n", count: 10_000)
        let ranges = EditorSelectionOccurrenceController.matchingRanges(in: text, selection: NSRange(location: 0, length: 4))
        XCTAssertEqual(ranges.count, 10_000)
        XCTAssertEqual(ranges.last, NSRange(location: 109_989, length: 4))
    }

    func testHighlightsAreTemporaryAndClearingPreservesOtherAttributes() async throws {
        let textView = NSTextView()
        textView.string = "foo bar foo"
        let storage = try XCTUnwrap(textView.textStorage)
        let layout = try XCTUnwrap(textView.layoutManager)
        storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: storage.length))
        storage.addAttribute(.backgroundColor, value: NSColor.yellow, range: NSRange(location: 0, length: storage.length))
        layout.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: NSRange(location: 8, length: 3))
        layout.addTemporaryAttribute(.backgroundColor, value: NSColor.green, forCharacterRange: NSRange(location: 4, length: 3))
        let controller = EditorSelectionOccurrenceController(textView: textView, highlightColorProvider: { .blue })
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        try await waitForHighlight(in: textView, at: 8)

        XCTAssertEqual(background(in: textView, at: 0), .blue)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor, .red)
        XCTAssertEqual(storage.attribute(.backgroundColor, at: 8, effectiveRange: nil) as? NSColor, .yellow)
        XCTAssertEqual(textView.string, "foo bar foo")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.refresh()

        XCTAssertNil(background(in: textView, at: 0))
        XCTAssertNil(background(in: textView, at: 8))
        XCTAssertEqual(background(in: textView, at: 4), .green)
        XCTAssertNotNil(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 8, effectiveRange: nil))
        XCTAssertEqual(storage.attribute(.backgroundColor, at: 8, effectiveRange: nil) as? NSColor, .yellow)
    }

    func testClearingAfterEditsRemovesShiftedHighlights() async throws {
        let textView = NSTextView()
        textView.string = "foo bar foo"
        let controller = EditorSelectionOccurrenceController(textView: textView, highlightColorProvider: { .blue })
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        try await waitForHighlight(in: textView, at: 8)

        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "prefix ")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.refresh()
        for location in 0..<(textView.string as NSString).length {
            XCTAssertNil(background(in: textView, at: location))
        }
        textView.string = "x"
        controller.refresh()
        XCTAssertNil(background(in: textView, at: 0))
    }

    func testRapidSelectionChangesAndEditsDiscardPendingHighlights() async throws {
        let textView = NSTextView()
        textView.string = "foo bar foo bar"
        let controller = EditorSelectionOccurrenceController(textView: textView, highlightColorProvider: { .blue })
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        textView.setSelectedRange(NSRange(location: 4, length: 3))
        controller.refresh()
        try await waitForHighlight(in: textView, at: 12)
        XCTAssertNil(background(in: textView, at: 0))
        XCTAssertNil(background(in: textView, at: 8))

        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        textView.string = "x"
        controller.refresh()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(background(in: textView, at: 0))
    }

    func testThemeRefreshChangesHighlightColor() async throws {
        let textView = NSTextView()
        textView.string = "foo foo"
        var color = NSColor.blue
        let controller = EditorSelectionOccurrenceController(textView: textView, highlightColorProvider: { color })
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        try await waitForHighlight(in: textView, at: 4)
        color = .red
        controller.refresh()
        try await waitForHighlight(in: textView, at: 4)
        XCTAssertEqual(background(in: textView, at: 4), .red)
    }

    func testMultipleSelectionsClearOccurrenceHighlights() async throws {
        let textView = NSTextView()
        textView.string = "foo bar foo"
        let controller = EditorSelectionOccurrenceController(textView: textView, highlightColorProvider: { .blue })
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        try await waitForHighlight(in: textView, at: 8)

        textView.selectedRanges = [
            NSValue(range: NSRange(location: 0, length: 3)),
            NSValue(range: NSRange(location: 8, length: 3)),
        ]
        controller.refresh()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(background(in: textView, at: 0))
        XCTAssertNil(background(in: textView, at: 8))
    }

    func testEditorSelectionEditingAndBracketHighlightsWorkTogether() async throws {
        let editor = EditorViewController()
        _ = editor.view
        editor.text = "(foo) foo"
        let textView = try XCTUnwrap(editor.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTextView }.first)
        var edits = 0
        editor.onTextChanged = { edits += 1 }
        textView.setSelectedRange(NSRange(location: 1, length: 3))
        try await waitForHighlight(in: textView, at: 6)
        XCTAssertEqual(edits, 0)

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertNil(background(in: textView, at: 6))
        XCTAssertNotNil(background(in: textView, at: 0))
        XCTAssertNotNil(background(in: textView, at: 4))

        textView.setSelectedRange(NSRange(location: 0, length: 1))
        try await waitForHighlight(in: textView, at: 0)
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertNotNil(background(in: textView, at: 0))
        XCTAssertNotNil(background(in: textView, at: 4))

        textView.setSelectedRange(NSRange(location: 1, length: 3))
        try await waitForHighlight(in: textView, at: 6)
        textView.insertText("bar", replacementRange: NSRange(location: 6, length: 3))
        XCTAssertEqual(edits, 1)
        XCTAssertEqual(editor.text, "(foo) bar")
        XCTAssertNil(background(in: textView, at: 6))

        editor.text = "x"
        XCTAssertNil(background(in: textView, at: 0))
    }

    func testReplacingSelectedMarkdownListWithNewlineCanDraw() async throws {
        let editor = EditorViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        defer { window.close() }
        editor.syntaxLanguage = .markdown
        let prefix = "# Notes\n\n## TODO\n" + String(repeating: "- A task with `inline code`\n", count: 10)
            + "\n## Query\n\n```sql\nSELECT * FROM items\nWHERE id = 42;\n```\n"
        let selected = "1. ddd\n2. dasdsa\n3. dsada\n4. safdd"
        editor.text = prefix + selected
        editor.view.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(editor.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTextView }.first)
        window.orderFront(nil)
        window.makeFirstResponder(textView)
        try await Task.sleep(nanoseconds: 200_000_000)
        let range = NSRange(location: prefix.utf16.count, length: selected.utf16.count)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        try await waitForHighlight(in: textView, at: range.location)
        window.displayIfNeeded()
        textView.insertNewline(nil)
        XCTAssertEqual(editor.text, prefix + "\n")
        window.displayIfNeeded()
        let image = NSImage(size: textView.bounds.size, flipped: true) { _ in
            textView.draw(textView.bounds)
            return true
        }
        XCTAssertNotNil(image.tiffRepresentation)
        try await Task.sleep(nanoseconds: 200_000_000)
        window.displayIfNeeded()
        XCTAssertNil(background(in: textView, at: range.location))

        textView.breakUndoCoalescing()
        let undoManager = try XCTUnwrap(textView.undoManager)
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertEqual(editor.text, prefix + selected)
        textView.setSelectedRange(range)
        try await waitForHighlight(in: textView, at: range.location)
        window.displayIfNeeded()
        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        XCTAssertEqual(editor.text, prefix + "\n")
        window.displayIfNeeded()
    }

    private func background(in textView: NSTextView, at location: Int) -> NSColor? {
        textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: location, effectiveRange: nil) as? NSColor
    }

    private func waitForHighlight(in textView: NSTextView, at location: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if background(in: textView, at: location) != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected occurrence highlight at \(location)", file: file, line: line)
    }
}
