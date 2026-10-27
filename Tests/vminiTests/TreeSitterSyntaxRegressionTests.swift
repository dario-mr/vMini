import AppKit
import XCTest
@testable import vmini

@MainActor
final class TreeSitterSyntaxRegressionTests: XCTestCase {
    private let theme = ThemeCatalog.palette(for: .default).syntaxTheme

    func testDiscardedStructuralParseForcesFullRecolor() async throws {
        let storage = NSTextStorage(string: "class Example {\n/* comment\n end */\nint x = 1;\n}\n")
        let session = TreeSitterSyntaxSession(language: .java)
        let initial = await session.highlight(text: storage.string, range: nil, edits: nil,
                                              baseRevision: 0, appliedRevision: 0, revision: 1)
        apply(try XCTUnwrap(initial), to: storage)
        let range = (storage.string as NSString).range(of: "/*")
        storage.replaceCharacters(in: range, with: "//")
        // Parsing completes, but a newer edit prevents this result from reaching the text storage.
        _ = await session.highlight(text: storage.string, range: range,
            edits: [.init(replacementRange: range, replacementString: "//", replacedText: "/*")],
            baseRevision: 1, appliedRevision: 1, revision: 2)
        let insertion = NSRange(location: range.location + 2, length: 0)
        storage.replaceCharacters(in: insertion, with: "x")
        let work = await session.highlight(text: storage.string, range: NSRange(location: range.location, length: 3),
            edits: [.init(replacementRange: insertion, replacementString: "x", replacedText: "")],
            baseRevision: 2, appliedRevision: 1, revision: 3)
        apply(try XCTUnwrap(work), to: storage)
        assertMatchesFresh(storage, language: .java)

        let nextRange = NSRange(location: insertion.location, length: 1)
        storage.replaceCharacters(in: nextRange, with: "y")
        let next = await session.highlight(text: storage.string, range: nextRange,
            edits: [.init(replacementRange: nextRange, replacementString: "y", replacedText: "x")],
            baseRevision: 3, appliedRevision: 3, revision: 4)
        let nextWork = try XCTUnwrap(next)
        XCTAssertLessThan(nextWork.range.length, storage.length, "Resume incremental highlighting after recovery")
        apply(nextWork, to: storage)
        assertMatchesFresh(storage, language: .java)
    }

    func testResetRecolorsBeyondRequestedRange() async throws {
        for missingEdits in [false, true] {
            let storage = NSTextStorage(string: "class Example {\n/* comment\n end */\nint x = 1;\n}\n")
            let session = TreeSitterSyntaxSession(language: .java)
            let initial = await session.highlight(text: storage.string, range: nil, edits: nil,
                                                  baseRevision: 0, appliedRevision: 0, revision: 1)
            apply(try XCTUnwrap(initial), to: storage)
            let range = (storage.string as NSString).range(of: "/*")
            storage.replaceCharacters(in: range, with: "//")
            let work = await session.highlight(text: storage.string, range: range,
                edits: missingEdits ? nil : [], baseRevision: missingEdits ? 1 : 2,
                appliedRevision: 1, revision: 3)
            apply(try XCTUnwrap(work), to: storage)
            assertMatchesFresh(storage, language: .java)
        }
    }

    func testInvalidEditAndLengthMismatchRecolorBeyondRequestedRange() {
        for invalidEdit in [false, true] {
            let storage = NSTextStorage(string: "class Example {\n/* comment\n end */\nint x = 1;\n}\n")
            let parser = TreeSitterSyntaxParser(language: .java)
            apply(parser.highlight(text: storage.string, in: nil), to: storage)
            let range = (storage.string as NSString).range(of: "/*")
            storage.replaceCharacters(in: range, with: "//x")
            let edits: [SyntaxHighlightEditContext] = invalidEdit
                ? [.init(replacementRange: range, replacementString: "//x", replacedText: "incorrect length")]
                : []
            apply(parser.highlight(text: storage.string, in: range, edits: edits), to: storage)
            assertMatchesFresh(storage, language: .java)
        }
    }

    func testPartialBashHighlightPreservesVariablesOnOtherLines() {
        let storage = NSTextStorage(string: "echo \"$HOME\nmiddle\n$USER\"\n")
        let parser = TreeSitterSyntaxParser(language: .bash)
        apply(parser.highlight(text: storage.string, in: nil), to: storage)
        let range = (storage.string as NSString).range(of: "middle")
        storage.replaceCharacters(in: range, with: "middLe")
        let work = parser.highlight(text: storage.string, in: range,
            edits: [.init(replacementRange: range, replacementString: "middLe", replacedText: "middle")])
        apply(work, to: storage)
        assertMatchesFresh(storage, language: .bash)
    }

    func testMarkdownBacktickEditsDoNotLeaveStaleColorsInLaterParagraphs() {
        for closingFirst in [false, true] {
            let storage = NSTextStorage(string: """
                # Notes

                ## TODO

                - refactor `Repository`?
                - see `Handler` → `Job::update` for update logic
                - ktlint unused imports

                ## Migration

                - double check the migration, for example `99.25 cases / 99 cases` would become `100 cases / 99 cases`, no?

                """)
            let parser = TreeSitterSyntaxParser(language: .markdown)
            apply(parser.highlight(text: storage.string, in: nil), to: storage)
            let word = (storage.string as NSString).range(of: "ktlint")
            let positions = closingFirst
                ? [NSMaxRange(word), word.location]
                : [word.location, NSMaxRange(word) + 1]
            for position in positions {
                let insertion = NSRange(location: position, length: 0)
                storage.replaceCharacters(in: insertion, with: "`")
                let work = parser.highlight(text: storage.string, in: NSRange(location: position, length: 1),
                    edits: [.init(replacementRange: insertion, replacementString: "`", replacedText: "")])
                apply(work, to: storage)
                assertMatchesFresh(storage, language: .markdown)
                let laterText = (storage.string as NSString).range(of: "double check")
                XCTAssertEqual(color(at: laterText.location, in: storage), theme.plainText)
            }
        }
    }

    func testMarkdownMultilineCodeSpanEditsRecolorTheWholeParagraph() {
        let storage = NSTextStorage(string: "before `code\n😀 continued` after\n\n- keep `other code`\n")
        let parser = TreeSitterSyntaxParser(language: .markdown)
        apply(parser.highlight(text: storage.string, in: nil), to: storage)
        let opening = (storage.string as NSString).range(of: "code").location - 1
        let closing = (storage.string as NSString).range(of: "` after").location
        for replacement in ["", "`"] {
            let range = NSRange(location: closing, length: replacement.isEmpty ? 1 : 0)
            let old = (storage.string as NSString).substring(with: range)
            storage.replaceCharacters(in: range, with: replacement)
            let work = parser.highlight(text: storage.string,
                in: NSRange(location: closing, length: replacement.utf16.count),
                edits: [.init(replacementRange: range, replacementString: replacement, replacedText: old)])
            XCTAssertLessThan(work.range.length, storage.length, "Unrelated paragraphs should remain outside the repaint")
            apply(work, to: storage)
            assertMatchesFresh(storage, language: .markdown)
            XCTAssertEqual(color(at: opening, in: storage), replacement.isEmpty ? theme.plainText : theme.inlineCode)
        }
    }

    func testMarkdownListBoundaryEditsMatchFreshHighlighting() {
        let storage = NSTextStorage(string: "# Heading\n\nBullet context\n- Bullet\n1. Numbered\n`inline`\n")
        let parser = TreeSitterSyntaxParser(language: .markdown)
        apply(parser.highlight(text: storage.string, in: nil), to: storage)
        let boundary = (storage.string as NSString).range(of: "\n-").location
        let number = (storage.string as NSString).range(of: "1.").location
        for (position, replacement) in [(0, "x"), (boundary, " "), (number, "x"), (0, "#"), (boundary, "\n")] {
            let range = NSRange(location: position, length: 1)
            let old = (storage.string as NSString).substring(with: range)
            storage.replaceCharacters(in: range, with: replacement)
            let work = parser.highlight(text: storage.string, in: NSRange(location: range.location, length: replacement.utf16.count),
                edits: [.init(replacementRange: range, replacementString: replacement, replacedText: old)])
            apply(work, to: storage)
            assertMatchesFresh(storage, language: .markdown)
        }
    }

    func testClippingHappensBeforeFenceOffsetIsApplied() {
        let storage = NSTextStorage(string: "prefix\n0123456789\nsuffix")
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.applyForegroundColor(theme.plainText, range: fullRange)
        let work = TreeSitterHighlightWork(range: NSRange(location: 3, length: 2), tokens: [
            .init(range: NSRange(location: 0, length: 10), role: .string)
        ])
        TreeSitterSyntaxHighlighter.apply(work, to: storage, theme: theme, offset: 7)
        for offset in 0..<storage.length {
            XCTAssertEqual(color(at: offset, in: storage), (10..<12).contains(offset) ? theme.string : theme.plainText)
        }
    }

    func testKotlinKeywordsAndQuotedLookalikes() {
        let text = "package demo\nimport kotlin.collections.List\ntypealias Names = List<String>\nclass Example { init {}\nfun test() = this\nval text = \"package import this\"\n}"
        let storage = NSTextStorage(string: text)
        apply(TreeSitterSyntaxParser(language: .kotlin).highlight(text: text, in: nil), to: storage)
        for word in ["package", "import", "typealias", "init", "this"] {
            XCTAssertEqual(color(at: (text as NSString).range(of: word).location, in: storage), theme.keyword, word)
        }
        XCTAssertEqual(color(at: (text as NSString).range(of: "package import this").location, in: storage), theme.string)
    }

    func testNestedSQLCommentsPreserveUnicodeOffsetsAndFollowingCode() {
        let text = "SELECT '😀';\r\n/* outer\r\n /* inner */ still comment 😀\r\n*/\r\nSELECT 42;"
        let storage = NSTextStorage(string: text)
        apply(TreeSitterSyntaxParser(language: .sql).highlight(text: text, in: nil), to: storage)
        let comment = (text as NSString).range(of: "/* outer\r\n /* inner */ still comment 😀\r\n*/")
        for offset in comment.location..<NSMaxRange(comment) {
            XCTAssertEqual(color(at: offset, in: storage), theme.comment)
        }
        XCTAssertEqual(color(at: (text as NSString).range(of: "SELECT", options: .backwards).location, in: storage), theme.keyword)
        XCTAssertEqual(color(at: (text as NSString).range(of: "42").location, in: storage), theme.variable)
    }

    func testSQLCommentDelimitersInsideQuotesAreNotMasked() {
        for text in [
            "SELECT '/* outer /* inner */ rest */';",
            "SELECT 'escaped \\' /* /* */ */';",
            "SELECT 'doubled '' /* /* */ */';",
            "SELECT \"/* /* */ */\", `/* /* */ */`, [/* /* */ */];",
            "SELECT $$/* /* */ */$$, $tag$/* /* */ */$tag$;",
            "-- /* /* */ */\nSELECT 1;",
            "SELECT 'unterminated /* /* */ */",
        ] {
            XCTAssertNil(SQLNestedComments.mask(in: text), text)
        }
    }

    func testNestedSQLCommentDelimiterEditsMatchFreshHighlighting() {
        let storage = NSTextStorage(string: "SELECT 1;\n/* outer\n /* inner */ still comment\n*/\nSELECT 2;")
        let parser = TreeSitterSyntaxParser(language: .sql)
        apply(parser.highlight(text: storage.string, in: nil), to: storage)
        for (old, replacement) in [("/* inner", "inner"), ("inner", "/* inner"), ("*/\nSELECT", "\nSELECT"), ("still", "still */")] {
            let range = (storage.string as NSString).range(of: old)
            XCTAssertNotEqual(range.location, NSNotFound)
            storage.replaceCharacters(in: range, with: replacement)
            let dirty = NSRange(location: range.location, length: replacement.utf16.count)
            let work = parser.highlight(text: storage.string, in: dirty,
                edits: [.init(replacementRange: range, replacementString: replacement, replacedText: old)])
            apply(work, to: storage)
            assertMatchesFresh(storage, language: .sql)
        }
    }

    func testFenceWorkCanBeComputedOffMainThreadAndCancelled() async throws {
        let text = "before\n```java\nclass Example {}\n```\nafter"
        let range = NSRange(location: 0, length: text.utf16.count)
        let result = await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            let cache = MarkdownFenceCache.makeFenceCache(in: text as NSString)
            XCTAssertNil(MarkdownFenceHighlighter.highlights(in: text, targetRange: range, fences: cache.blocks,
                                                            isCancelled: { true }))
            return MarkdownFenceHighlighter.highlights(in: text, targetRange: range, fences: cache.blocks)
        }.value
        let highlights = try XCTUnwrap(result)
        XCTAssertEqual(highlights.count, 1)
        let storage = NSTextStorage(string: text)
        storage.applyForegroundColor(theme.plainText, range: range)
        for highlight in highlights {
            TreeSitterSyntaxHighlighter.apply(highlight.work, to: storage, theme: theme, offset: highlight.offset)
        }
        XCTAssertEqual(color(at: (text as NSString).range(of: "class").location, in: storage), theme.keyword)
        XCTAssertEqual(color(at: 0, in: storage), theme.plainText)
        XCTAssertEqual(color(at: (text as NSString).range(of: "after").location, in: storage), theme.plainText)
    }

    func testMarkdownListMarkersUpdatePromptlyAfterSQLFence() async throws {
        let prefix = "# Notes\n```sql\nUPDATE items SET deleted_at = NULL WHERE id = 1;\n```\n\n"
        let storage = NSTextStorage(string: prefix)
        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: .shared,
            textStorageProvider: { storage },
            syntaxThemeProvider: { self.theme },
            baseFontProvider: { NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) }
        )
        func waitForColor(_ expected: NSColor, at offset: Int, timeout: TimeInterval) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while color(at: offset, in: storage) != expected, Date() < deadline {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            XCTAssertEqual(color(at: offset, in: storage), expected)
        }

        controller.refresh(language: .markdown)
        let sqlOffset = (prefix as NSString).range(of: "UPDATE").location
        try await waitForColor(theme.keyword, at: sqlOffset, timeout: 5)
        for fragment in ["1. first\n", "2. second\n", "3. ", "\n- "] {
            let markerLocation = storage.length + (fragment.hasPrefix("\n") ? 1 : 0)
            let range = NSRange(location: storage.length, length: 0)
            storage.replaceCharacters(in: range, with: fragment)
            controller.handleProcessedEditing(
                editedMask: .editedCharacters,
                editedRange: NSRange(location: range.location, length: fragment.utf16.count),
                language: .markdown,
                editContext: .init(replacementRange: range, replacementString: fragment, replacedText: "")
            )
            // A nearby fence must not make even a small edit wait for query recompilation.
            try await waitForColor(theme.listMarker, at: markerLocation, timeout: 0.25)
            XCTAssertEqual(color(at: sqlOffset, in: storage), theme.keyword)
        }
    }

    private func apply(_ work: TreeSitterHighlightWork, to storage: NSTextStorage) {
        storage.applyForegroundColor(theme.plainText, range: work.range)
        TreeSitterSyntaxHighlighter.apply(work, to: storage, theme: theme)
    }

    private func color(at offset: Int, in storage: NSTextStorage) -> NSColor? {
        storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
    }

    private func assertMatchesFresh(_ storage: NSTextStorage, language: SyntaxLanguage,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let fresh = NSTextStorage(string: storage.string)
        apply(TreeSitterSyntaxParser(language: language).highlight(text: fresh.string, in: nil), to: fresh)
        let differences = (0..<storage.length).filter { color(at: $0, in: storage) != color(at: $0, in: fresh) }
        XCTAssertTrue(differences.isEmpty, "Different UTF-16 offsets: \(differences.prefix(20))", file: file, line: line)
    }
}
