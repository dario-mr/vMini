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

    func testCurrentMatchBackgroundAcrossThemesAndNavigation() throws {
        let originalTheme = ThemeManager.shared.selectedThemeID
        defer { ThemeManager.shared.setThemeID(originalTheme) }
        let (editor, textView, window) = try makeEditor("localhost localhost localhost")
        defer { window.orderOut(nil) }
        editor.performSearchAction(.find)
        let search = editor.searchController
        setQuery("localhost", in: search)
        let layout = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)

        for theme in ThemeID.allCases {
            ThemeManager.shared.setThemeID(theme)
            textView.appearance = NSAppearance(named: theme.preferredAppearance)
            for step in 0..<6 {
                window.makeFirstResponder(step.isMultiple(of: 2) ? textView : search.panel.searchField)
                editor.performSearchAction(.next)
                let selected = textView.selectedRange()
                let other = try XCTUnwrap(search.matches.first { $0 != selected })
                let selectedRect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: selected, actualCharacterRange: nil), in: container)
                let otherRect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: other, actualCharacterRange: nil), in: container)
                let bitmap = try renderBackground(textView)
                // The interior must match the ordinary yellow highlight, not AppKit's gray selection.
                let interior = try pixel(bitmap, at: NSPoint(x: selectedRect.minX + 3, y: selectedRect.minY + 3))
                XCTAssertEqual(interior, try pixel(bitmap, at: NSPoint(x: otherRect.minX + 3, y: otherRect.minY + 3)), theme.rawValue)
                XCTAssertNotEqual(interior, try pixel(bitmap, at: NSPoint(x: selectedRect.minX, y: selectedRect.minY + 3)), theme.rawValue)
                XCTAssertEqual(textView.selectedRange(), selected)
                XCTAssertTrue(window.firstResponder === (step.isMultiple(of: 2) ? textView : search.panel.searchField.currentEditor()))
            }
            let beforeSyntaxColor = try renderBackground(textView).tiffRepresentation
            textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: 1))
            XCTAssertEqual(beforeSyntaxColor, try renderBackground(textView).tiffRepresentation, "Syntax colors must not tint the search outline in \(theme.rawValue)")
        }
    }

    func testSearchBackgroundFallsBackForQueryChangesAndClose() throws {
        let (editor, textView, window) = try makeEditor("localhost localhost")
        defer { window.orderOut(nil) }
        editor.performSearchAction(.replace)
        let search = editor.searchController
        setQuery("localhost", in: search)
        let layout = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        let currentMatch = layout.currentMatch

        func assertNativeBackground(file: StaticString = #filePath, line: UInt = #line) throws {
            let actual = try renderBackground(textView).tiffRepresentation
            layout.currentMatch = nil
            defer { layout.currentMatch = currentMatch }
            XCTAssertEqual(actual, try renderBackground(textView).tiffRepresentation, file: file, line: line)
        }

        func renderedText() throws -> NSBitmapImageRep {
            let container = try XCTUnwrap(textView.textContainer)
            let glyphs = layout.glyphRange(forCharacterRange: textView.selectedRange(), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            let bitmap = try XCTUnwrap(textView.bitmapImageRepForCachingDisplay(in: rect))
            textView.needsDisplay = true
            textView.cacheDisplay(in: rect, to: bitmap)
            return bitmap
        }

        window.makeFirstResponder(textView)
        let focused = try renderBackground(textView).tiffRepresentation
        let focusedText = try renderedText()
        window.makeFirstResponder(search.panel.replacementField)
        let highlighted = try renderBackground(textView).tiffRepresentation
        XCTAssertEqual(focused, highlighted)
        let fieldText = try renderedText()
        // AppKit may change the glyph foreground with focus; the fill and border must stay the same.
        for (x, y) in [(focusedText.pixelsWide / 2, focusedText.pixelsHigh - 3), (0, focusedText.pixelsHigh / 2)] {
            XCTAssertEqual(focusedText.colorAt(x: x, y: y), fieldText.colorAt(x: x, y: y))
        }
        layout.currentMatch = nil
        XCTAssertNotEqual(highlighted, try renderBackground(textView).tiffRepresentation)
        layout.currentMatch = currentMatch
        textView.setSelectedRange(NSRange(location: 1, length: 3))
        try assertNativeBackground()
        textView.setSelectedRanges([NSValue(range: search.matches[0]), NSValue(range: search.matches[1])], affinity: .downstream, stillSelecting: false)
        try assertNativeBackground()
        for query in ["missing", ""] {
            setQuery(query, in: search)
            try assertNativeBackground()
        }
        setQuery("localhost", in: search)
        search.close()
        XCTAssertTrue(window.firstResponder === textView)
        // Also check inactive selection after closing, where the original bug was visible.
        window.makeFirstResponder(nil)
        try assertNativeBackground()
    }

    func testCurrentMatchBackgroundCoversWrappedAndMultilineText() throws {
        for query in ["localhost localhost localhost", "localhost\nlocalhost"] {
            let (editor, textView, window) = try makeEditor(query)
            defer { window.orderOut(nil) }
            editor.performSearchAction(.find)
            setQuery(query, in: editor.searchController)
            let layout = try XCTUnwrap(textView.layoutManager)
            let container = try XCTUnwrap(textView.textContainer)
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: 100, height: 1000)
            let selection = textView.selectedRange()
            let highlighted = try renderBackground(textView)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            let ordinary = try renderBackground(textView)
            let glyphs = layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
            var rects: [NSRect] = []
            layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, _ in
                rects.append(rect)
            }
            XCTAssertGreaterThan(rects.count, 1)
            for rect in rects where rect.width > 6 {
                let point = NSPoint(x: rect.minX + 3, y: rect.minY + 3)
                XCTAssertEqual(try pixel(highlighted, at: point), try pixel(ordinary, at: point))
            }
        }
    }

    func testJavaSearchKeepsHighlightAfterEditorFocusAndScrolledNavigation() async throws {
        let source = "class RoomService {\n" + (0..<60).map {
            "    String room\($0)(String roomId) { return roomId; }\n"
        }.joined() + "}"
        let (editor, textView, window) = try makeEditor(source)
        defer { window.orderOut(nil) }
        editor.syntaxLanguage = .java
        editor.performSearchAction(.find)
        let search = editor.searchController
        setQuery("roomId", in: search)
        try await Task.sleep(nanoseconds: 150_000_000)
        let layout = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        let currentMatch = layout.currentMatch

        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (source as NSString).length / 2, length: 0))
        for _ in 0..<3 {
            editor.performSearchAction(.next)
            let range = textView.selectedRange()
            XCTAssertTrue(search.matches.contains(range))
            XCTAssertTrue(window.firstResponder === textView)
            XCTAssertGreaterThan(textView.visibleRect.minY, 0)
            let actual = try renderBackground(textView)
            layout.currentMatch = nil
            XCTAssertNotEqual(actual.tiffRepresentation, try renderBackground(textView).tiffRepresentation)
            layout.currentMatch = currentMatch
            let rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
            let point = NSPoint(x: rect.minX + 3, y: rect.minY + 3)
            window.makeFirstResponder(search.panel.searchField)
            XCTAssertEqual(try pixel(actual, at: point), try pixel(renderBackground(textView), at: point))
            window.makeFirstResponder(textView)
        }
    }

    private func renderBackground(_ textView: NSTextView) throws -> NSBitmapImageRep {
        let layout = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layout.ensureLayout(for: container)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(textView.bounds.width)),
                                                  pixelsHigh: Int(ceil(textView.bounds.height)), bitsPerSample: 8,
                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            textView.backgroundColor.setFill()
            textView.bounds.fill()
            layout.drawBackground(forGlyphRange: layout.glyphRange(for: container), at: .zero)
        }
        return bitmap
    }

    private func pixel(_ bitmap: NSBitmapImageRep, at point: NSPoint) throws -> NSColor {
        try XCTUnwrap(bitmap.colorAt(x: Int(point.x), y: bitmap.pixelsHigh - Int(point.y) - 1))
    }

    private func makeEditor(_ text: String) throws -> (EditorViewController, NSTextView, NSWindow) {
        _ = NSApplication.shared
        let editor = EditorViewController()
        _ = editor.view
        editor.text = text
        let window = SearchTestWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
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

private final class SearchTestWindow: NSWindow {
    // Exercise active selection drawing without activating a test window on the user's desktop.
    override var isKeyWindow: Bool { true }
}
