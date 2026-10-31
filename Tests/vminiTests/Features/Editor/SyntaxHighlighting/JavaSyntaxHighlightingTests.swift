import AppKit
import XCTest
@testable import vmini

@MainActor
final class JavaSyntaxHighlightingTests: XCTestCase {
    private let theme = ThemeCatalog.palette(for: .default).syntaxTheme
    private let font = EditorFontResolver.font(for: .fallback, size: 13)

    func testIncrementalEditsMatchFreshHighlighting() {
        let storage = NSTextStorage(string: "class Example {\r\n String text = \"😀 café\";\r\n /* comment\r\n end */\r\n int value() { return 42; }\r\n}\r\n")
        let parser = TreeSitterSyntaxParser(language: .java)
        apply(parser.highlight(text: storage.string, in: nil), to: storage)
        for (old, replacement) in [
            ("😀", "😀🙂"), ("String", "Object"), ("return", "returX"), ("returX", "return"),
            ("/*", "//"), ("//", "/*"), ("*/", ""), ("end", "end */"),
            ("\"😀🙂 café\"", "\"\"\"\r\n😀 text block\r\n\"\"\""),
            ("class", "// prefix\r\nclass"), ("// prefix\r\n", ""),
        ] {
            let range = (storage.string as NSString).range(of: old)
            XCTAssertNotEqual(range.location, NSNotFound)
            let edit = SyntaxHighlightEditContext(replacementRange: range, replacementString: replacement, replacedText: old)
            storage.replaceCharacters(in: range, with: replacement)
            let dirty = NSRange(location: range.location, length: replacement.utf16.count)
            let work = parser.highlight(text: storage.string, in: dirty, edits: [edit])
            apply(work, to: storage)
            XCTAssertTrue(matchesFresh(storage), "After replacing \(old) with \(replacement)")
        }
    }

    func testBatchedEditsAndIncompleteCodeMatchFreshHighlighting() {
        let storage = NSTextStorage(string: "class Example { String text = \"😀\"; int number = 42; }\n")
        let parser = TreeSitterSyntaxParser(language: .java)
        apply(parser.highlight(text: storage.string, in: nil), to: storage)
        var state: UInt64 = 7
        let fragments = ["/*", "*/", "\"", "\n", "😀", "\r\n", "String", "return", "", "x"]
        for _ in 0..<40 {
            var edits: [SyntaxHighlightEditContext] = []
            for _ in 0..<3 {
                state = state &* 6_364_136_223_846_793_005 &+ 1
                let indices = Array(storage.string.indices) + [storage.string.endIndex]
                let index = Int(state % UInt64(indices.count))
                let end = min(index + 1, indices.count - 1)
                let range = NSRange(indices[index]..<indices[end], in: storage.string)
                let replacement = fragments[Int((state >> 32) % UInt64(fragments.count))]
                edits.append(.init(replacementRange: range, replacementString: replacement,
                                   replacedText: (storage.string as NSString).substring(with: range)))
                storage.replaceCharacters(in: range, with: replacement)
            }
            apply(parser.highlight(text: storage.string, in: nil, edits: edits), to: storage)
            XCTAssertTrue(matchesFresh(storage))
        }
    }

    func testSessionRecoversAfterSkippedRequestsAndRejectsOldResults() async {
        let session = TreeSitterSyntaxSession(language: .java)
        _ = await session.highlight(text: "class First {}", range: nil, edits: nil, baseRevision: 0, appliedRevision: 0, revision: 1)
        let source = "class Second { String text = \"😀\"; }"
        let work = await session.highlight(text: source, range: nil, edits: [], baseRevision: 2, appliedRevision: 1, revision: 3)
        let storage = NSTextStorage(string: source)
        apply(work!, to: storage)
        XCTAssertTrue(matchesFresh(storage))
        let stale = await session.highlight(text: "class Old {}", range: nil, edits: nil, baseRevision: 1, appliedRevision: 1, revision: 2)
        XCTAssertNil(stale)
    }

    func testUnicodeAcrossParserChunkBoundaries() {
        let text = "//" + String(repeating: " ", count: 2_045) + "😀\nclass Last { String value = \"café\"; }"
        let storage = NSTextStorage(string: text)
        apply(TreeSitterSyntaxParser(language: .java).highlight(text: text, in: nil), to: storage)
        for (word, color) in [("😀", theme.comment), ("class", theme.keyword), ("String", theme.builtin), ("café", theme.string)] {
            XCTAssertEqual(storage.attribute(.foregroundColor, at: (text as NSString).range(of: word).location,
                                             effectiveRange: nil) as? NSColor, color)
        }
    }

    func testControllerCoalescesRapidEditsAndKeepsEditorsIndependent() async throws {
        let first = NSTextStorage(string: "class First {\n /* comment */\n String value = \"😀\";\n}\n")
        let second = NSTextStorage(string: "class Second {\n int value = 42;\n}\n")
        let firstController = controller(for: first)
        let secondController = controller(for: second)
        firstController.refresh(language: .java)
        secondController.refresh(language: .java)
        try await waitUntil { self.matchesFresh(first) && self.matchesFresh(second) }
        for (storage, controller, old, replacement) in [
            (first, firstController, "*/", ""),
            (second, secondController, "42", "0b1010"),
            (first, firstController, "First", "😀 Prefix\nFirst"),
            (second, secondController, "int", "String"),
        ] {
            let range = (storage.string as NSString).range(of: old)
            storage.replaceCharacters(in: range, with: replacement)
            controller.handleProcessedEditing(
                editedMask: .editedCharacters,
                editedRange: NSRange(location: range.location, length: replacement.utf16.count),
                language: .java,
                editContext: .init(replacementRange: range, replacementString: replacement, replacedText: old)
            )
        }
        try await waitUntil { self.matchesFresh(first) && self.matchesFresh(second) }
    }

    func testJavaFenceDoesNotColorSurroundingMarkdown() {
        let text = "class outside\n```java\nclass Inside { String text = \"hi\"; }\n```\nclass after\n"
        let storage = NSTextStorage(string: text)
        HighlighterRegistry.shared.highlighter(for: .markdown).highlight(
            textStorage: storage, in: nil, baseFont: font, theme: theme, registry: .shared
        )
        for word in ["class outside", "class after"] {
            XCTAssertNil(storage.attribute(.foregroundColor, at: (text as NSString).range(of: word).location, effectiveRange: nil))
        }
        XCTAssertEqual(storage.attribute(.foregroundColor, at: (text as NSString).range(of: "class Inside").location,
                                         effectiveRange: nil) as? NSColor, theme.keyword)
    }

    func testTypingUndoAndRedoNearEndPreserveViewportAfterHighlighting() async throws {
        try await assertTypingUndoAndRedoPreserveViewport(language: .java)
    }

    func testTypingUndoAndRedoInJavaFencePreserveViewportAfterHighlighting() async throws {
        try await assertTypingUndoAndRedoPreserveViewport(language: .markdown)
    }

    private func assertTypingUndoAndRedoPreserveViewport(language: SyntaxLanguage) async throws {
        let previousDefaults = EditorSettings.userDefaults
        let defaults = UserDefaults(suiteName: "JavaViewport.\(UUID().uuidString)")!
        defaults.set(true, forKey: UserDefaultsKeys.editorWordWrapEnabled)
        defaults.set(14, forKey: UserDefaultsKeys.editorFontSize)
        EditorSettings.userDefaults = defaults
        defer { EditorSettings.userDefaults = previousDefaults }
        let editor = EditorViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 900, height: 600))
        editor.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        defer { window.close() }
        editor.syntaxLanguage = language
        let java = "class Example {\n" + (0..<400).map {
            "    int value\($0)() { return \($0); }\n"
        }.joined() + "}\n"
        editor.text = language == .markdown
            ? "# Notes\n\n## Query\n```sql\nSELECT * FROM example;\n```\n\n```java\n" + java + "```\n\nAfter code.\n"
            : java
        editor.view.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertGreaterThan(scroll.contentView.bounds.height, 100)
        let textView = try XCTUnwrap(scroll.documentView as? NSTextView)
        let storage = try XCTUnwrap(textView.textStorage)
        window.orderFront(nil)
        window.makeFirstResponder(textView)
        let keyword = (editor.text as NSString).range(of: "return", options: .backwards)
        let color = ThemeManager.shared.syntaxTheme.keyword
        try await waitUntil {
            storage.attribute(.foregroundColor, at: keyword.location, effectiveRange: nil) as? NSColor == color
        }
        let location = NSMaxRange((editor.text as NSString).range(of: "{", options: .backwards,
            range: NSRange(location: 0, length: keyword.location)))
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        window.displayIfNeeded()
        let documentHeight = textView.frame.height
        let origin = scroll.contentView.bounds.origin
        XCTAssertGreaterThan(origin.y, 1_000)
        let layout = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        func visibleCharacters() -> NSRange {
            let rect = textView.visibleRect.offsetBy(dx: -textView.textContainerOrigin.x,
                                                    dy: -textView.textContainerOrigin.y)
            return layout.characterRange(forGlyphRange: layout.glyphRange(forBoundingRect: rect, in: container),
                                         actualGlyphRange: nil)
        }
        let firstVisibleCharacter = visibleCharacters().location
        XCTAssertGreaterThan(visibleCharacters().length, 0)

        textView.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        let highlighted = expectation(description: "Asynchronous highlighting finished")
        let observation = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main
        ) { _ in highlighted.fulfill() }
        await fulfillment(of: [highlighted], timeout: 3)
        NotificationCenter.default.removeObserver(observation)
        window.displayIfNeeded()
        XCTAssertEqual(textView.selectedRange(), NSRange(location: location + 1, length: 0))
        XCTAssertEqual(textView.frame.height, documentHeight, accuracy: 0.5)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, origin.y, accuracy: 0.5)
        XCTAssertEqual(visibleCharacters().location, firstVisibleCharacter)
        XCTAssertGreaterThan(visibleCharacters().length, 0)

        textView.breakUndoCoalescing()
        let undoManager = try XCTUnwrap(textView.undoManager)
        for redo in [false, true, false] {
            if redo {
                XCTAssertTrue(undoManager.canRedo)
                undoManager.redo()
            } else {
                XCTAssertTrue(undoManager.canUndo)
                undoManager.undo()
            }
            let highlighted = expectation(description: "Undo/redo highlighting finished")
            let observation = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main
            ) { _ in highlighted.fulfill() }
            await fulfillment(of: [highlighted], timeout: 3)
            NotificationCenter.default.removeObserver(observation)
            window.displayIfNeeded()
            XCTAssertEqual(textView.selectedRange(), NSRange(location: location + (redo ? 1 : 0), length: 0))
            XCTAssertEqual(textView.frame.height, documentHeight, accuracy: 0.5)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, origin.y, accuracy: 0.5)
            XCTAssertEqual(visibleCharacters().location, firstVisibleCharacter)
            XCTAssertGreaterThan(visibleCharacters().length, 0)
            XCTAssertTrue(matchesFresh(storage, language: language))
        }
    }

    private func controller(for storage: NSTextStorage) -> EditorSyntaxHighlightController {
        EditorSyntaxHighlightController(
            highlighterRegistry: .shared, textStorageProvider: { storage },
            syntaxThemeProvider: { self.theme }, baseFontProvider: { self.font }
        )
    }

    private func apply(_ work: TreeSitterHighlightWork, to storage: NSTextStorage) {
        storage.addAttribute(.foregroundColor, value: theme.plainText, range: work.range)
        TreeSitterSyntaxHighlighter.apply(work, to: storage, theme: theme)
    }

    private func matchesFresh(_ storage: NSTextStorage, language: SyntaxLanguage = .java) -> Bool {
        let fresh = NSTextStorage(string: storage.string)
        fresh.addAttribute(.foregroundColor, value: theme.plainText, range: NSRange(location: 0, length: fresh.length))
        HighlighterRegistry.shared.highlighter(for: language).highlight(
            textStorage: fresh, in: nil, baseFont: font, theme: theme, registry: .shared
        )
        for offset in 0..<storage.length {
            if storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
                != fresh.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor { return false }
        }
        return true
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while !condition() {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                XCTFail("Highlighting did not finish")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
