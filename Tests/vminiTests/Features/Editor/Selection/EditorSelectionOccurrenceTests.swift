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

    func testOccurrenceBordersDoNotModifyTextOrOtherAttributes() async throws {
        let textView = EditorTextView()
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

        XCTAssertFalse(isOccurrenceHighlighted(in: textView, at: 0))
        XCTAssertTrue(isOccurrenceHighlighted(in: textView, at: 8))
        XCTAssertEqual(textView.selectionOccurrenceHighlightColor, .blue)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor, .red)
        XCTAssertEqual(storage.attribute(.backgroundColor, at: 8, effectiveRange: nil) as? NSColor, .yellow)
        XCTAssertEqual(textView.string, "foo bar foo")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.refresh()

        XCTAssertFalse(isOccurrenceHighlighted(in: textView, at: 0))
        XCTAssertFalse(isOccurrenceHighlighted(in: textView, at: 8))
        XCTAssertEqual(background(in: textView, at: 4), .green)
        XCTAssertNotNil(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: 8, effectiveRange: nil))
        XCTAssertEqual(storage.attribute(.backgroundColor, at: 8, effectiveRange: nil) as? NSColor, .yellow)
    }

    func testClearingAfterEditsRemovesShiftedHighlights() async throws {
        let textView = EditorTextView()
        textView.string = "foo bar foo"
        let controller = EditorSelectionOccurrenceController(textView: textView, highlightColorProvider: { .blue })
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        try await waitForHighlight(in: textView, at: 8)

        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "prefix ")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.refresh()
        XCTAssertTrue(textView.selectionOccurrenceHighlightRanges.isEmpty)
        textView.string = "x"
        controller.refresh()
        XCTAssertTrue(textView.selectionOccurrenceHighlightRanges.isEmpty)
    }

    func testRapidSelectionChangesAndEditsDiscardPendingHighlights() async throws {
        let textView = EditorTextView()
        textView.string = "foo bar foo bar"
        let controller = EditorSelectionOccurrenceController(textView: textView, highlightColorProvider: { .blue })
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        textView.setSelectedRange(NSRange(location: 4, length: 3))
        controller.refresh()
        try await waitForHighlight(in: textView, at: 12)
        XCTAssertFalse(isOccurrenceHighlighted(in: textView, at: 0))
        XCTAssertFalse(isOccurrenceHighlighted(in: textView, at: 8))

        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        textView.string = "x"
        controller.refresh()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(textView.selectionOccurrenceHighlightRanges.isEmpty)
    }

    func testThemeRefreshChangesHighlightColor() async throws {
        let textView = EditorTextView()
        textView.string = "foo foo"
        var color = NSColor.blue
        let controller = EditorSelectionOccurrenceController(textView: textView, highlightColorProvider: { color })
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        controller.refresh()
        try await waitForHighlight(in: textView, at: 4)
        color = .red
        controller.refresh()
        try await waitForHighlight(in: textView, at: 4)
        XCTAssertEqual(textView.selectionOccurrenceHighlightColor, .red)
    }

    func testMultipleSelectionsClearOccurrenceHighlights() async throws {
        let textView = EditorTextView()
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
        XCTAssertTrue(textView.selectionOccurrenceHighlightRanges.isEmpty)
    }

    func testEditorSelectionEditingAndBracketHighlightsWorkTogether() async throws {
        let editor = EditorViewController()
        _ = editor.view
        editor.text = "(foo) foo"
        let textView = try XCTUnwrap(editor.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? EditorTextView }.first)
        var edits = 0
        editor.onTextChanged = { edits += 1 }
        textView.setSelectedRange(NSRange(location: 1, length: 3))
        try await waitForHighlight(in: textView, at: 6)
        XCTAssertEqual(edits, 0)

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertFalse(isOccurrenceHighlighted(in: textView, at: 6))
        XCTAssertNotNil(background(in: textView, at: 0))
        XCTAssertNotNil(background(in: textView, at: 4))

        textView.setSelectedRange(NSRange(location: 0, length: 1))
        XCTAssertTrue(textView.selectionOccurrenceHighlightRanges.isEmpty)
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertNotNil(background(in: textView, at: 0))
        XCTAssertNotNil(background(in: textView, at: 4))

        textView.setSelectedRange(NSRange(location: 1, length: 3))
        try await waitForHighlight(in: textView, at: 6)
        textView.insertText("bar", replacementRange: NSRange(location: 6, length: 3))
        XCTAssertEqual(edits, 1)
        XCTAssertEqual(editor.text, "(foo) bar")
        XCTAssertFalse(isOccurrenceHighlighted(in: textView, at: 6))

        editor.text = "x"
        XCTAssertTrue(textView.selectionOccurrenceHighlightRanges.isEmpty)
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
        let textView = try XCTUnwrap(editor.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? EditorTextView }.first)
        window.orderFront(nil)
        window.makeFirstResponder(textView)
        try await Task.sleep(nanoseconds: 200_000_000)
        let range = NSRange(location: prefix.utf16.count, length: selected.utf16.count)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
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
        window.displayIfNeeded()
        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        XCTAssertEqual(editor.text, prefix + "\n")
        window.displayIfNeeded()
    }

    func testRendererJoinsMultilineUnicodeBordersAndIgnoresStaleRanges() throws {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.containerSize = NSSize(width: 200, height: 100)
        textView.string = "😀 foo\nbar\nother"
        let layout = try XCTUnwrap(textView.layoutManager)
        layout.ensureLayout(for: try XCTUnwrap(textView.textContainer))

        func redPixelCounts(for ranges: [NSRange], color: NSColor?, dirtyRect: NSRect? = nil) throws -> [Int: Int] {
            let image = NSImage(size: textView.bounds.size, flipped: true) { _ in
                NSColor.white.setFill()
                textView.bounds.fill()
                let dirtyRect = dirtyRect ?? textView.bounds
                NSBezierPath(rect: dirtyRect).addClip()
                EditorSelectionOccurrenceRenderer.draw(
                    in: textView,
                    dirtyRect: dirtyRect,
                    ranges: ranges,
                    color: color,
                    joinLineFragments: true
                )
                return true
            }
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            var countsByRow: [Int: Int] = [:]
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if pixel.redComponent > 0.8, pixel.greenComponent < 0.8, pixel.blueComponent < 0.8 {
                        // Both selected rows contain this column; their shared edge must stay open.
                        if (10..<20).contains(x) { countsByRow[y, default: 0] += 1 }
                    }
                }
            }
            return countsByRow
        }

        let range = (textView.string as NSString).range(of: "😀 foo\nbar")
        let redCounts = try redPixelCounts(for: [range], color: .red)
        let rows = Set(redCounts.keys)
        let firstRow = try XCTUnwrap(rows.min())
        let lastRow = try XCTUnwrap(rows.max())
        XCTAssertGreaterThan(lastRow - firstRow, 14)
        let interiorRows = redCounts.filter { $0.key > firstRow + 3 && $0.key < lastRow - 3 }
        XCTAssertTrue(interiorRows.isEmpty, "multiline selection should not draw a border across each row")
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let bounds = layout.boundingRect(forGlyphRange: glyphs, in: try XCTUnwrap(textView.textContainer))
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        for y in [bounds.minY - 2, bounds.maxY + 1] {
            XCTAssertFalse(try redPixelCounts(
                for: [range], color: .red,
                dirtyRect: NSRect(x: 0, y: y, width: textView.bounds.width, height: 1)
            ).isEmpty, "Border-only dirty rectangles must still draw the selection")
        }
        XCTAssertTrue(try redPixelCounts(for: [range], color: nil).isEmpty)
        XCTAssertTrue(try redPixelCounts(for: [
            NSRange(location: -1, length: 1), NSRange(location: NSNotFound, length: 1),
            NSRange(location: 0, length: Int.max), NSRange(location: 500, length: 1),
        ], color: .red).isEmpty)
    }

    func testRendererKeepsMultilineSidesStraightBetweenRoundedOuterCorners() throws {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.containerSize = NSSize(width: 220, height: 160)
        let selected = String(repeating: "line\n", count: 6)
        textView.string = selected + "suffix"
        let range = NSRange(location: 0, length: selected.utf16.count)
        let layout = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let bounds = layout.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        for filled in [false, true] {
            let image = NSImage(size: textView.bounds.size, flipped: true) { _ in
                NSColor.white.setFill()
                textView.bounds.fill()
                EditorSelectionOccurrenceRenderer.draw(
                    in: textView, dirtyRect: textView.bounds, ranges: [range],
                    color: .red, filled: filled, joinLineFragments: true
                )
                return true
            }
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let scaleX = CGFloat(bitmap.pixelsWide) / image.size.width
            let scaleY = CGFloat(bitmap.pixelsHigh) / image.size.height
            for x in [bounds.minX - 2, bounds.maxX + 2] {
                let greens = try (Int((bounds.minY + 4) * scaleY)..<Int((bounds.maxY - 4) * scaleY)).map { y in
                    try XCTUnwrap(bitmap.colorAt(x: Int(x * scaleX), y: y)?.usingColorSpace(.deviceRGB)).greenComponent
                }
                XCTAssertLessThan(try XCTUnwrap(greens.max()) - XCTUnwrap(greens.min()), 0.01,
                                  "Joined rows must have a straight side for both the fill and outline")
            }
        }
    }

    func testRendererPreservesUnselectedPrefixAndSuffixAcrossLines() throws {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.containerSize = NSSize(width: 240, height: 120)
        textView.string = "prefix 😀 selected\nend suffix\nother"
        let text = textView.string as NSString
        let selection = text.range(of: "😀 selected\nend")
        let layout = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layout.ensureLayout(for: container)
        let image = NSImage(size: textView.bounds.size, flipped: true) { _ in
            NSColor.white.setFill()
            textView.bounds.fill()
            EditorSelectionOccurrenceRenderer.draw(
                in: textView, dirtyRect: textView.bounds, ranges: [selection],
                color: .red, filled: true, joinLineFragments: true
            )
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        for (word, selected) in [("prefix", false), ("selected", true), ("end", true), ("suffix", false)] {
            let glyphs = layout.glyphRange(forCharacterRange: text.range(of: word), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            let pixel = try XCTUnwrap(bitmap.colorAt(
                x: Int(rect.midX * CGFloat(bitmap.pixelsWide) / image.size.width),
                y: Int(rect.midY * CGFloat(bitmap.pixelsHigh) / image.size.height)
            )?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(pixel.greenComponent < 0.9, selected, word)
        }
        XCTAssertEqual(text.substring(with: selection), "😀 selected\nend")
    }

    func testDraggingInvalidatesThePaddedSelectionOutline() {
        let textView = SelectionInvalidationTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        textView.string = "prefix selected\nsecond line\nthird line"
        for range in [NSRange(location: 7, length: 13), NSRange(location: 7, length: 24), NSRange(location: 7, length: 4)] {
            textView.invalidatedEntireView = false
            textView.setSelectedRanges([NSValue(range: range)], affinity: .downstream, stillSelecting: true)
            XCTAssertTrue(textView.invalidatedEntireView, "Drag updates must redraw outside AppKit's glyph rectangles")
            XCTAssertEqual(textView.selectedRange(), range)
        }
    }

    private func background(in textView: NSTextView, at location: Int) -> NSColor? {
        textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: location, effectiveRange: nil) as? NSColor
    }

    private func isOccurrenceHighlighted(in textView: EditorTextView, at location: Int) -> Bool {
        textView.selectionOccurrenceHighlightRanges.contains { NSLocationInRange(location, $0) }
    }

    private func waitForHighlight(in textView: EditorTextView, at location: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if isOccurrenceHighlighted(in: textView, at: location) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected occurrence border at \(location)", file: file, line: line)
    }
}

private final class SelectionInvalidationTextView: EditorTextView {
    var invalidatedEntireView = false

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue { invalidatedEntireView = true }
            super.needsDisplay = newValue
        }
    }
}
