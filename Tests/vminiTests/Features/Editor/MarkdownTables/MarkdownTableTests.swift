import AppKit
import XCTest
@testable import vmini

final class MarkdownTableTests: XCTestCase {
    private func parse(_ source: String) -> [MarkdownTable] {
        let text = source as NSString
        return MarkdownTableParser.parse(text)
    }

    func testRangesEscapesCodeAndOptionalOuterPipes() throws {
        let source = "Intro 😀\r\n\r\n  Name | Value | Empty\r\n  :--- | :---: | ---:\r\n  a\\|b | ``x\\|`y`` |\r\n\r\nEnd"
        let text = source as NSString
        let table = try XCTUnwrap(parse(source).first)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.alignments, [.left, .center, .right])
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[2].cells.map { text.substring(with: $0) }, ["a\\|b", "``x\\|`y``"])
        XCTAssertEqual(table.rows[2].pipes.count, 2)
        XCTAssertEqual(text.substring(with: table.range), source.components(separatedBy: "\r\n")[2...4].joined(separator: "\r\n") + "\r\n")
        for row in table.rows {
            XCTAssertTrue(row.range.location >= table.range.location && NSMaxRange(row.range) <= NSMaxRange(table.range))
            for pipe in row.pipes { XCTAssertEqual(text.substring(with: NSRange(location: pipe, length: 1)), "|") }
        }
    }

    func testEmptyRaggedCellsAndBackslashParity() throws {
        let source = "| A | B | C |\n| - | :-: | -: |\n| | a\\\\| b | extra |\n| short |\n\n"
        let table = try XCTUnwrap(parse(source).first)
        XCTAssertEqual(table.rows[2].cells.map { (source as NSString).substring(with: $0) }, ["", "a\\\\", "b", "extra"])
        XCTAssertEqual(table.rows[3].cells.count, 1)
        XCTAssertEqual(parse("| A |\n---\n| data |").count, 1)
        XCTAssertEqual(parse("| A | B |\n| - | - |\n| `unclosed | text |").first?.rows.last?.cells.count, 2)
    }

    func testInvalidAndCodeBlocksStayPlain() {
        for source in ["a | b", "a | b\n---", "a | b\n--- | :", "a | b\n--- | bad",
                       "heading\n---", "    a | b\n    --- | ---", "> a | b\n> --- | ---",
                       "```md\na | b\n--- | ---\n```", "~~~\na | b\n--- | ---\n~~~",
                       "```\na | b\n--- | ---"] {
            XCTAssertTrue(parse(source).isEmpty, source)
        }
        let tables = parse("a | b\n--- | ---\nx | y\n# Heading\n\n| c |\n| - |\nend")
        XCTAssertEqual(tables.count, 2)
        XCTAssertEqual(tables[0].rows.count, 3)
    }

    func testBodyRowsContinueUntilBlankLineOrBlockBoundary() throws {
        for newline in ["\n", "\r\n"] {
            let tableSource = ["| A | B |", "| --- | --- |", "| a | b |", ""].joined(separator: newline)
            for paragraph in ["plain text", "escaped \\| pipe", "`code|pipe`"] {
                let source = tableSource + paragraph + newline + newline + tableSource
                let tables = parse(source)
                XCTAssertEqual(tables.count, 2)
                let first = try XCTUnwrap(tables.first)
                XCTAssertEqual(first.rows.count, 4)
                XCTAssertEqual(first.range, NSRange(location: 0, length: (tableSource + paragraph + newline).utf16.count))
                XCTAssertEqual(tables.last?.range.location, (tableSource + paragraph + newline + newline).utf16.count)
            }
        }
    }

    func testCodeSpanPipesMustBeEscapedAndInlineHTMLIsNotABlock() throws {
        let source = "| A | B |\n| --- | --- |\n| `a|b` | c |\n| `a\\|b` | c |\n<https://example.com> | yes\n# End"
        let table = try XCTUnwrap(parse(source).first)
        let text = source as NSString
        XCTAssertEqual(table.rows.count, 5)
        XCTAssertEqual(table.rows[2].cells.map { text.substring(with: $0) }, ["`a", "b`", "c"])
        XCTAssertEqual(table.rows[3].cells.map { text.substring(with: $0) }, ["`a\\|b`", "c"])
        XCTAssertEqual(text.substring(with: table.rows[4].cells[0]), "<https://example.com>")
    }

    @MainActor
    func testHTMLBlocksAreNeitherRenderedNorFormatted() throws {
        let rawTable = "A | B\n--- | ---\nx | y"
        let actualTable = "| C | D |\n| --- | --- |\n| z | w |"
        for (opening, closing) in [("<!--", "-->"), ("<pre>", "</pre>"), ("<script>", "</script>"),
                                   ("<?processing", "?>"), ("<![CDATA[", "]]>"), ("<div>", "</div>")] {
            let html = opening + "\n\n" + rawTable + "\n\n" + closing
            // A blank line ends generic HTML blocks such as <div>, unlike comments and <pre>.
            let block = opening == "<div>" ? opening + "\n" + rawTable + "\n" + closing : html
            let source = "😀\n\n" + block + "\n\n" + actualTable
            let editor = EditorViewController()
            editor.syntaxLanguage = .markdown
            editor.text = source
            _ = editor.view
            XCTAssertEqual(parse(source).count, 1, opening)
            editor.formatMarkdownTable()
            XCTAssertTrue(editor.text.hasPrefix("😀\n\n" + block + "\n\n"), opening)
            XCTAssertTrue(editor.text.contains("| C   | D   |"), opening)
        }
    }

    func testHTMLBoundaryEditsInvalidateDistantCachedTables() {
        var source = "<!--\n\nA | B\n--- | ---\nx | y\n\n-->\n\nC | D\n--- | ---\nz | w"
        let cache = MarkdownTableCache()
        cache.reset(source as NSString, enabled: true)
        func replace(_ needle: String, with replacement: String) {
            let old = source as NSString
            let range = old.range(of: needle)
            source = old.replacingCharacters(in: range, with: replacement)
            cache.update(source as NSString, edit: SyntaxHighlightEditContext(
                replacementRange: range, replacementString: replacement, replacedText: needle))
            XCTAssertEqual(cache.tables, parse(source))
        }
        XCTAssertEqual(cache.tables.count, 1)
        replace("<!--", with: "ordinary text")
        XCTAssertEqual(cache.tables.count, 2)
        replace("ordinary text", with: "<pre>")
        XCTAssertTrue(cache.tables.isEmpty)
        replace("-->", with: "</pre>")
        XCTAssertEqual(cache.tables.count, 1)
        replace("z | w", with: "plain body")
        replace("<pre>", with: "<prf>")
        replace("<prf>", with: "<pre>")
        replace("</pre>", with: "not closed")
        XCTAssertTrue(cache.tables.isEmpty)
    }

    func testIncrementalCacheMatchesFullParsingAcrossEdits() {
        var source = "before\n\na | b\n--- | ---\nx | y\n\nmiddle\n\n| c | d |\n| - | - |\n| z | w |\n\nafter"
        let cache = MarkdownTableCache()
        cache.reset(source as NSString, enabled: true)
        func replace(_ needle: String, with replacement: String) {
            let old = source as NSString
            let range = old.range(of: needle)
            XCTAssertNotEqual(range.location, NSNotFound)
            guard range.location != NSNotFound else { return }
            let edit = SyntaxHighlightEditContext(replacementRange: range, replacementString: replacement, replacedText: needle)
            source = old.replacingCharacters(in: range, with: replacement)
            cache.update(source as NSString, edit: edit)
            XCTAssertEqual(cache.tables, parse(source), "After replacing \(needle.debugDescription)")
        }
        replace("x | y", with: "😀\\|z | value")
        XCTAssertLessThan(cache.highlightRange.length, (source as NSString).length)
        replace("value", with: "`a|b`")
        replace("--- | ---", with: "--- | incomplete")
        replace("--- | incomplete", with: ":--- | ---:")
        replace("before\n\n", with: "")
        replace("middle", with: "```\ncode")
        replace("```\ncode", with: "middle")
        replace("\n\nmiddle\n\n", with: "\n")
        replace(source, with: "| single |\n| - |")
        replace(source, with: "")
    }

    func testCellInsertionsAndDeletionsKeepHighlightingLocalUntilTableBoundariesChange() throws {
        var source = "a|b\n---|---\nitem|`value`\n\nc|d\n---|---\nx|y"
        let cache = MarkdownTableCache()
        cache.reset(source as NSString, enabled: true)
        func replace(_ needle: String, with replacement: String) {
            let old = source as NSString
            let range = old.range(of: needle)
            source = old.replacingCharacters(in: range, with: replacement)
            cache.update(source as NSString, edit: SyntaxHighlightEditContext(
                replacementRange: range, replacementString: replacement, replacedText: needle))
            XCTAssertEqual(cache.tables, parse(source))
        }
        replace("`value`", with: "value`")
        XCTAssertEqual(cache.highlightRange.length, 0)
        replace("value`", with: "`value`")
        XCTAssertEqual(cache.highlightRange.length, 0)
        replace("item", with: "longer item")
        XCTAssertEqual(cache.highlightRange.length, 0)
        replace("---|---", with: "bad|---")
        XCTAssertGreaterThan(cache.highlightRange.length, 0)
        XCTAssertEqual(cache.tables.count, 1)
    }

    @MainActor
    func testNativeCellEditsKeepHighlightingLocal() throws {
        let editor = EditorViewController()
        editor.syntaxLanguage = .markdown
        editor.text = "| A | B |\n| --- | --- |\n| x | `value` |\n"
        let textView = try XCTUnwrap(findTextView(editor.view))
        let manager = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        let marker = (editor.text as NSString).range(of: "`value`")
        textView.insertText("", replacementRange: NSRange(location: marker.location, length: 1))
        XCTAssertEqual(manager.markdownTables.highlightRange.length, 0)
        XCTAssertEqual(manager.markdownTables.tables, parse(editor.text))
    }

    @MainActor
    func testPartialHighlightFindsWholeTableAndExcludesHTML() throws {
        let source = "<pre>\nA | B\n--- | ---\nx | y\n</pre>\n\n| Header | Other |\n| --- | --- |\n| x | y |\n\nTail"
        let text = source as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let storage = NSTextStorage(string: source, attributes: [.font: font, .foregroundColor: theme.plainText])
        let highlighter = MarkdownSyntaxHighlighter()
        let header = text.range(of: "Header")
        highlighter.highlight(textStorage: storage, in: nil, baseFont: font, theme: theme, registry: .shared)
        highlighter.highlight(textStorage: storage, in: header, baseFont: font, theme: theme, registry: .shared)
        let styledFont = try XCTUnwrap(storage.attribute(.font, at: header.location, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(NSFontManager.shared.weight(of: styledFont), NSFontManager.shared.weight(of: font))
        let body = text.range(of: "| x | y |")
        highlighter.highlight(textStorage: storage, in: body, baseFont: font, theme: theme, registry: .shared)
        XCTAssertLessThan(try XCTUnwrap(storage.attribute(.foregroundColor, at: body.location, effectiveRange: nil) as? NSColor).alphaComponent, 0.1)
        XCTAssertEqual(storage.attribute(.font, at: text.range(of: "A | B").location, effectiveRange: nil) as? NSFont, font)
        XCTAssertEqual(storage.string, source)
    }

    @MainActor
    func testFormattingPreservesCellSelectionsAndRebasesPositionsOutsideTables() throws {
        let editor = EditorViewController()
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        defer { window.orderOut(nil) }
        editor.syntaxLanguage = .markdown
        let source = "Intro 😀\r\n\r\nname|qty\r\n---|---:\r\nrow|😀value\r\n\r\nnext|n\r\n---|---\r\nlast|cell\r\n\r\nTail unchanged"
        let text = source as NSString
        let textView = try XCTUnwrap(findTextView(editor.view))
        window.makeFirstResponder(textView)
        let value = text.range(of: "😀value").location + 2
        let tail = text.range(of: "Tail unchanged").location + 5
        let cell = text.range(of: "cell").location + 2
        for selection in [NSRange(location: value, length: 0), NSRange(location: value, length: 3),
                          NSRange(location: 1, length: 0), NSRange(location: tail, length: 0),
                          NSRange(location: value, length: cell - value), NSRange(location: 0, length: text.length)] {
            editor.text = source
            textView.setSelectedRange(selection)
            editor.formatMarkdownTable()
            let formatted = editor.text as NSString
            let expectedStart: Int
            let expectedEnd: Int
            if selection.location == value {
                expectedStart = formatted.range(of: "😀value").location + 2
                expectedEnd = NSMaxRange(selection) == cell ? formatted.range(of: "cell").location + 2
                    : expectedStart + selection.length
            } else {
                expectedStart = selection.location == tail ? formatted.range(of: "Tail unchanged").location + 5 : selection.location
                expectedEnd = selection.length == text.length ? formatted.length : expectedStart
            }
            XCTAssertEqual(textView.selectedRange(), NSRange(location: expectedStart, length: expectedEnd - expectedStart))
            editor.formatMarkdownTable()
            XCTAssertEqual(textView.selectedRange(), NSRange(location: expectedStart, length: expectedEnd - expectedStart))
        }
    }

    @MainActor
    func testFormatterPreservesContentsAlignmentLineEndingsAndIsIdempotent() throws {
        let source = "  a|long|c\r\n  :--|:-:|--:\r\n  `a\\|b`|x\\|y|😀\r\n  q| |r\r\n"
        let table = try XCTUnwrap(parse(source).first)
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let result = MarkdownTableFormatter.format(table, in: source as NSString, font: font)
        let formattedTable = try XCTUnwrap(parse(result).first, result)
        XCTAssertEqual(formattedTable.alignments, table.alignments)
        for index in [0, 2, 3] {
            XCTAssertEqual(formattedTable.rows[index].cells.map { (result as NSString).substring(with: $0) },
                           table.rows[index].cells.map { (source as NSString).substring(with: $0) })
        }
        XCTAssertEqual(result.filter { $0 == "\r\n" }.count, 4)
        XCTAssertTrue(result.hasPrefix("  | a      |"), result)
        XCTAssertEqual(MarkdownTableFormatter.format(formattedTable, in: result as NSString, font: font), result)
        let ascii = "a|long|c\n:--|:-:|--:\nabcdef|x|z"
        let asciiTable = try XCTUnwrap(parse(ascii).first)
        let aligned = MarkdownTableFormatter.format(asciiTable, in: ascii as NSString, font: font)
        XCTAssertEqual(aligned, "| a      | long |   c |\n| :----- | :--: | --: |\n| abcdef |  x   |   z |")
    }

    func testIncrementalCacheMatchesFullParsingAtEveryEditBoundary() {
        let source = "intro\n\na|b\n-|:-:\nx|y\n\ntext\n\n| c |\n| - |\nz\n\n```\n| code |\n| - |\n```\n\nend" as NSString
        for location in 0...source.length {
            for replacement in ["", "|", "\n", "\n\n", "`", "~~~\n", "😀"] {
                for length in [0, min(7, source.length - location)] {
                    let cache = MarkdownTableCache()
                    cache.reset(source, enabled: true)
                    let range = NSRange(location: location, length: length)
                    let changed = source.replacingCharacters(in: range, with: replacement)
                    cache.update(changed as NSString, edit: SyntaxHighlightEditContext(
                        replacementRange: range, replacementString: replacement, replacedText: source.substring(with: range)))
                    XCTAssertEqual(cache.tables, parse(changed), "\(range), \(replacement.debugDescription)")
                }
            }
        }
    }

    @MainActor
    func testFormatterKeepsExtraCellsAndPadsMissingCells() throws {
        let source = "a|b\n-|--\nx|y|ignored\n|z|\n"
        let table = try XCTUnwrap(parse(source).first)
        let result = MarkdownTableFormatter.format(table, in: source as NSString, font: .monospacedSystemFont(ofSize: 14, weight: .regular))
        let formatted = try XCTUnwrap(parse(result).first)
        XCTAssertEqual(formatted.columnCount, 2)
        XCTAssertEqual(formatted.rows[2].cells.count, 3)
        XCTAssertEqual((result as NSString).substring(with: formatted.rows[2].cells[2]), "ignored")
        XCTAssertEqual(formatted.rows[3].cells.count, 2)
    }

    @MainActor
    func testNativeLayoutSeparatorsFollowWrappedRowsAndFontChanges() throws {
        let source = "| Name | Description |\n| --- | --- |\n| item | a very long description that wraps across several native text fragments |\n| final | value |"
        let table = try XCTUnwrap(parse(source).first)
        let storage = NSTextStorage(string: source)
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        for size: CGFloat in [12, 20] {
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), range: table.range)
            for width: CGFloat in [200, 800] {
                container.containerSize.width = width
                let separators = MarkdownTableRendering.separators(for: table, layoutManager: manager)
                XCTAssertEqual(separators.count, 3)
                XCTAssertTrue(separators[0].isHeader)
                XCTAssertFalse(separators[1].isHeader)
                XCTAssertTrue(separators.allSatisfy { $0.start.x == separators[0].start.x && $0.end.x == separators[0].end.x })
                for (separator, row) in zip(separators, [table.rows[1], table.rows[2], table.rows[3]]) {
                    let glyphs = manager.glyphRange(forCharacterRange: row.range, actualCharacterRange: nil)
                    let fragment = manager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
                    let firstFragment = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                    let expectedY = separator.isHeader ? firstFragment.union(fragment).midY : fragment.maxY - 0.5
                    XCTAssertEqual(separator.start.y, expectedY)
                }
                XCTAssertGreaterThan(separators[1].start.y, separators[0].start.y)
                XCTAssertEqual(storage.string, source)
            }
        }
    }

    @MainActor
    func testTableTintSpansTheBlockAndStaysBeneathTextBackgrounds() throws {
        let source = "| Name | Description |\n| --- | --- |\n| x | a longer value |"
        let table = try XCTUnwrap(parse(source).first)
        let storage = NSTextStorage(string: source)
        let manager = EditorSearchLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 300))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), range: table.range)
        manager.markdownTables.reset(source as NSString, enabled: true)
        manager.outlineColor = .black
        let glyphs = manager.glyphRange(forCharacterRange: table.range, actualCharacterRange: nil)
        let separators = MarkdownTableRendering.separators(for: table, layoutManager: manager)
        let header = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let bodyGlyphs = manager.glyphRange(forCharacterRange: table.rows[2].range, actualCharacterRange: nil)
        let body = manager.lineFragmentRect(forGlyphAt: bodyGlyphs.location, effectiveRange: nil)
        func render() throws -> NSBitmapImageRep {
            let image = NSImage(size: NSSize(width: 400, height: 300), flipped: true) { rect in
                NSColor.white.setFill()
                rect.fill()
                manager.drawBackground(forGlyphRange: glyphs, at: .zero)
                return true
            }
            return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        }
        let bitmap = try render()
        let x = Int((separators[0].start.x + separators[0].end.x) / 2)
        let headerColor = try XCTUnwrap(bitmap.colorAt(x: x, y: Int(header.midY)))
        let bodyColor = try XCTUnwrap(bitmap.colorAt(x: x, y: Int(body.midY)))
        XCTAssertLessThan(headerColor.brightnessComponent, bodyColor.brightnessComponent)
        XCTAssertLessThan(bodyColor.brightnessComponent, 1)
        XCTAssertGreaterThan(bodyColor.brightnessComponent, 0.95)
        XCTAssertEqual(bitmap.colorAt(x: 390, y: Int(body.midY))?.brightnessComponent, 1)
        storage.addAttribute(.backgroundColor, value: NSColor.red, range: table.rows[2].range)
        let highlighted = try render()
        let highlightColor = try XCTUnwrap(highlighted.colorAt(x: x, y: Int(body.midY)))
        XCTAssertEqual(highlightColor.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(highlightColor.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(storage.string, source)
    }

    @MainActor
    func testOutlineEnclosesNativeLayoutAtBothBackingScales() throws {
        for source in ["| Header | Value |\n| --- | --- |", "| Header | Value |\n| --- | --- |\n| item | a long cell that wraps across several native fragments |\n| last | value |"] {
            let table = try XCTUnwrap(parse(source).first)
            let storage = NSTextStorage(string: source)
            let manager = EditorSearchLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: 200, height: 300))
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            manager.markdownTables.reset(source as NSString, enabled: true)
            manager.outlineColor = .black
            for size: CGFloat in [12, 20] {
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), range: table.range)
                for width: CGFloat in [200, 800] {
                    container.containerSize.width = width
                    let glyphs = manager.glyphRange(forCharacterRange: table.range, actualCharacterRange: nil)
                    let separators = MarkdownTableRendering.separators(for: table, layoutManager: manager)
                    let header = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                    let last = manager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
                    let origin = NSPoint(x: 12, y: 14)
                    for scale: CGFloat in [1, 2] {
                        let canvas = NSSize(width: ceil((separators[0].end.x + 30) * scale), height: ceil((last.maxY + 40) * scale))
                        let image = NSImage(size: canvas, flipped: true) { rect in
                            NSColor.white.setFill()
                            rect.fill()
                            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
                            NSBezierPath(rect: NSRect(x: origin.x, y: origin.y, width: width, height: last.maxY)).addClip()
                            manager.drawBackground(forGlyphRange: glyphs, at: origin)
                            return true
                        }
                        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                        let columns = try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager))
                        let leftEdge = columns.outerEdges[0].map { $0 - 0.5 / scale } ?? max(separators[0].start.x - 3, header.minX)
                        let rightEdge = columns.outerEdges[table.columnCount].map { $0 + 0.5 / scale } ?? min(separators[0].end.x + 3, header.maxX)
                        let left = Int(floor((leftEdge + origin.x) * scale))
                        let right = Int(ceil((rightEdge + origin.x) * scale)) - 1
                        let top = Int(floor((header.minY + origin.y) * scale))
                        let bottom = Int(ceil((last.maxY + origin.y) * scale)) - 1
                        let x = (left + right) / 2
                        let y = Int((header.midY + origin.y) * scale)
                        for point in [(x, top), (x, bottom), (left, y), (right, y)] {
                            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)).brightnessComponent, 0.85)
                        }
                        // A single device-pixel stroke, with tint inside and untouched editor background outside.
                        let interiorColor = try XCTUnwrap(bitmap.colorAt(x: left + 1, y: y))
                        let outlineColor = try XCTUnwrap(bitmap.colorAt(x: left, y: y))
                        XCTAssertGreaterThan(interiorColor.brightnessComponent, outlineColor.brightnessComponent)
                        XCTAssertEqual(bitmap.colorAt(x: left - 1, y: y)?.brightnessComponent, 1)
                        XCTAssertEqual(bitmap.colorAt(x: left, y: top)?.brightnessComponent, 1)
                        for row in (top + Int(4 * scale))..<(bottom - Int(4 * scale)) {
                            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: left, y: row)).brightnessComponent, 0.85)
                            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: right, y: row)).brightnessComponent, 0.85)
                        }
                        XCTAssertEqual(storage.string, source)
                    }
                }
            }
        }
    }

    @MainActor
    func testDelimiterRuleReplacesItsOwnRowAndDisappearsWhenSelected() throws {
        _ = NSApplication.shared
        let editor = EditorViewController()
        editor.syntaxLanguage = .markdown
        editor.text = "| column A | column B | column C |\n| -------- | -------- | -------- |\n| aaa | 1 | aa |\n| bbb | 22 | ddd |"
        let textView = try XCTUnwrap(findTextView(editor.view))
        let manager = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        manager.outlineColor = .black
        let table = try XCTUnwrap(manager.markdownTables.tables.first)
        let glyphs = manager.glyphRange(forCharacterRange: table.range, actualCharacterRange: nil)
        let delimiterGlyphs = manager.glyphRange(forCharacterRange: table.rows[1].range, actualCharacterRange: nil)
        let delimiter = manager.lineFragmentRect(forGlyphAt: delimiterGlyphs.location, effectiveRange: nil)
        let headerGlyphs = manager.glyphRange(forCharacterRange: table.rows[0].range, actualCharacterRange: nil)
        let header = manager.lineFragmentRect(forGlyphAt: NSMaxRange(headerGlyphs) - 1, effectiveRange: nil)
        let separator = try XCTUnwrap(MarkdownTableRendering.separators(for: table, layoutManager: manager).first)
        let x = Int((separator.start.x + separator.end.x) / 2)
        func renderBackground() throws -> NSBitmapImageRep {
            let image = NSImage(size: NSSize(width: 600, height: 300), flipped: true) { rect in
                NSColor.white.setFill()
                rect.fill()
                manager.drawBackground(forGlyphRange: glyphs, at: .zero)
                return true
            }
            return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        }
        let normal = try renderBackground()
        let rowBackground = try XCTUnwrap(normal.colorAt(x: x, y: Int(delimiter.midY) + 3)).brightnessComponent
        let columns = try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager))
        let leftEdge = columns.outerEdges[0] ?? separator.start.x
        let rightEdge = columns.outerEdges[table.columnCount] ?? separator.end.x
        for column in (Int(ceil(leftEdge)) + 2)..<(Int(floor(rightEdge)) - 2) {
            XCTAssertLessThan(try XCTUnwrap(normal.colorAt(x: column, y: Int(delimiter.midY))).brightnessComponent, rowBackground - 0.02)
        }
        let oldDivider = try XCTUnwrap(normal.colorAt(x: x, y: Int(header.maxY) - 1)).brightnessComponent
        let headerBackground = try XCTUnwrap(normal.colorAt(x: x, y: Int(header.maxY) - 3)).brightnessComponent
        XCTAssertEqual(oldDivider, headerBackground, accuracy: 0.01)
        let aboveSeparator = try XCTUnwrap(normal.colorAt(x: x, y: Int(delimiter.midY) - 3)).brightnessComponent
        XCTAssertEqual(aboveSeparator, headerBackground, accuracy: 0.01)
        XCTAssertLessThan(aboveSeparator, rowBackground)
        textView.setSelectedRange(NSRange(location: table.rows[1].contentRange.location + 3, length: 0))
        let selected = try renderBackground()
        XCTAssertGreaterThan(try XCTUnwrap(selected.colorAt(x: x, y: Int(delimiter.midY))).brightnessComponent,
                             try XCTUnwrap(normal.colorAt(x: x, y: Int(delimiter.midY))).brightnessComponent + 0.02)
        textView.setSelectedRange(NSRange(location: table.rows[2].range.location, length: 0))
        let restored = try renderBackground()
        XCTAssertLessThan(try XCTUnwrap(restored.colorAt(x: x, y: Int(delimiter.midY))).brightnessComponent, rowBackground - 0.02)
    }

    @MainActor
    func testDelimiterVisibilityFollowsSelectionWithoutChangingTextOrLayout() throws {
        _ = NSApplication.shared
        let editor = EditorViewController()
        editor.syntaxLanguage = .markdown
        let source = "Intro 😀\r\n\r\n| Name | Value |\r\n| :--- | ---: |\r\n| item | value |\r\n"
        editor.text = source
        let textView = try XCTUnwrap(findTextView(editor.view))
        let manager = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        let storage = try XCTUnwrap(textView.textStorage)
        let table = try XCTUnwrap(manager.markdownTables.tables.first)
        let row = table.rows[1]
        let glyphs = manager.glyphRange(forCharacterRange: row.range, actualCharacterRange: nil)
        let fragment = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let originalAttributes = NSAttributedString(attributedString: storage)
        manager.outlineColor = .black
        func delimiterInkContrast() throws -> CGFloat {
            func render(glyphs: Bool) throws -> NSBitmapImageRep {
                let image = NSImage(size: NSSize(width: 600, height: 300), flipped: true) { rect in
                    NSColor.white.setFill()
                    rect.fill()
                    let allGlyphs = manager.glyphRange(forCharacterRange: table.range, actualCharacterRange: nil)
                    manager.drawBackground(forGlyphRange: allGlyphs, at: .zero)
                    if glyphs { manager.drawGlyphs(forGlyphRange: allGlyphs, at: .zero) }
                    return true
                }
                return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            }
            let background = try render(glyphs: false)
            let bitmap = try render(glyphs: true)
            let separator = try XCTUnwrap(MarkdownTableRendering.separators(for: table, layoutManager: manager).first)
            var contrast: CGFloat = 0
            for y in (Int(ceil(fragment.minY)) + 3)..<(Int(floor(fragment.maxY)) - 3) {
                for x in (Int(ceil(separator.start.x)) + 2)..<(Int(floor(separator.end.x)) - 2) {
                    let before = try XCTUnwrap(background.colorAt(x: x, y: y)).brightnessComponent
                    let after = try XCTUnwrap(bitmap.colorAt(x: x, y: y)).brightnessComponent
                    contrast = max(contrast, abs(after - before))
                }
            }
            return contrast
        }
        XCTAssertEqual(try delimiterInkContrast(), 0, accuracy: 0.01)
        textView.setSelectedRange(NSRange(location: row.contentRange.location + 3, length: 0))
        XCTAssertGreaterThan(try delimiterInkContrast(), 0.1)
        var textChanges = 0
        editor.onTextChanged = { textChanges += 1 }
        for (selection, visible) in [
            (NSRange(location: table.rows[0].range.location, length: 0), false),
            (NSRange(location: row.range.location, length: 0), true),
            (NSRange(location: row.contentRange.location + 3, length: 1), true),
            (NSRange(location: table.range.location, length: row.range.location - table.range.location), false),
            (NSRange(location: row.range.location - 1, length: 2), true),
            (NSRange(location: table.rows[2].range.location, length: 0), false)
        ] {
            textView.setSelectedRange(selection)
            let color = try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: row.contentRange.location, effectiveRange: nil) as? NSColor)
            XCTAssertEqual(color.alphaComponent > 0, visible, "\(selection)")
            XCTAssertEqual(textView.selectedRange(), selection)
            XCTAssertEqual(manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil), fragment)
        }
        textView.selectedRanges = [NSValue(range: NSRange(location: table.rows[0].range.location, length: 1)),
                                   NSValue(range: NSRange(location: row.contentRange.location, length: 1))]
        XCTAssertGreaterThan(try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: row.contentRange.location, effectiveRange: nil) as? NSColor).alphaComponent, 0)
        XCTAssertNil(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: table.rows[2].cells[0].location, effectiveRange: nil))
        XCTAssertEqual(storage.string, source)
        XCTAssertTrue(storage.isEqual(to: originalAttributes))
        XCTAssertEqual(textChanges, 0)
    }

    @MainActor
    func testDelimiterCaretAtEndOfDocumentRespectsLineEndings() throws {
        let editor = EditorViewController()
        editor.syntaxLanguage = .markdown
        let textView = try XCTUnwrap(findTextView(editor.view))
        let manager = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        for ending in ["", "\n", "\r\n"] {
            editor.text = "| A | B |\n| --- | --- |" + ending
            let row = try XCTUnwrap(manager.markdownTables.tables.first).rows[1]
            textView.setSelectedRange(NSRange(location: (editor.text as NSString).length, length: 0))
            let color = try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: row.contentRange.location, effectiveRange: nil) as? NSColor)
            XCTAssertEqual(color.alphaComponent > 0, ending.isEmpty)
            textView.setSelectedRange(NSRange(location: NSMaxRange(row.contentRange), length: 0))
            XCTAssertGreaterThan(try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: row.contentRange.location, effectiveRange: nil) as? NSColor).alphaComponent, 0)
        }
    }

    @MainActor
    func testHiddenDelimitersFollowEditsUndoAndLanguageChanges() throws {
        _ = NSApplication.shared
        let editor = EditorViewController()
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        defer { window.orderOut(nil) }
        editor.syntaxLanguage = .markdown
        let source = "| A | B |\n| --- | --- |\n| x | y |\n\n| C | D |\n| --- | --- |\n| z | w |"
        editor.text = source
        let textView = try XCTUnwrap(findTextView(editor.view))
        window.makeFirstResponder(textView)
        let manager = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        let undo = try XCTUnwrap(textView.undoManager)
        undo.removeAllActions()
        textView.insertText("😀\n", replacementRange: NSRange(location: 0, length: 0))
        let shifted = try XCTUnwrap(manager.markdownTables.tables.first).rows[1]
        XCTAssertEqual(try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: shifted.contentRange.location, effectiveRange: nil) as? NSColor).alphaComponent, 0)
        XCTAssertNil(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil))
        textView.setSelectedRange(shifted.contentRange)
        let pasteboard = NSPasteboard.withUniqueName()
        XCTAssertEqual(textView.selectedRange(), shifted.contentRange)
        XCTAssertTrue(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes))
        XCTAssertEqual(pasteboard.string(forType: .string), (editor.text as NSString).substring(with: shifted.contentRange))
        textView.breakUndoCoalescing()
        undo.removeAllActions()
        textView.insertText("invalid", replacementRange: shifted.cells[0])
        XCTAssertEqual(manager.markdownTables.tables.count, 1)
        XCTAssertNil(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: shifted.contentRange.location, effectiveRange: nil))
        undo.undo()
        XCTAssertEqual(editor.text, "😀\n" + source)
        XCTAssertEqual(manager.markdownTables.tables.count, 2)
        undo.redo()
        XCTAssertEqual(manager.markdownTables.tables.count, 1)
        editor.syntaxLanguage = .plaintext
        for index in 0..<(editor.text as NSString).length {
            XCTAssertNil(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: index, effectiveRange: nil))
        }
        editor.text = source
        editor.syntaxLanguage = .markdown
        let restored = try XCTUnwrap(manager.markdownTables.tables.first).rows[1]
        XCTAssertEqual(try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: restored.contentRange.location, effectiveRange: nil) as? NSColor).alphaComponent, 0)
    }

    @MainActor
    func testFormattingTargetsSelectedTablesOrAllTablesAsOneUndoOperation() throws {
        _ = NSApplication.shared
        let editor = EditorViewController()
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        defer { window.orderOut(nil) }
        editor.syntaxLanguage = .markdown
        let textView = try XCTUnwrap(findTextView(editor.view))
        window.makeFirstResponder(textView)
        let undo = try XCTUnwrap(textView.undoManager)
        let prefix = "Intro 😀\r\n\r\n"
        let first = "name|n\r\n---|---:\r\na|1\r\n"
        let middle = "\r\nBetween untouched\r\n\r\n```md\r\ncode|table\r\n---|---\r\n```\r\n\r\n"
        let second = "fruit|qty\r\n---|---:\r\napple|12\r\n"
        let suffix = "\r\nTail 😀 unchanged"
        let source = prefix + first + middle + second + suffix
        let text = source as NSString
        let firstRange = text.range(of: first)
        let secondRange = text.range(of: second)
        let tables = parse(source)
        XCTAssertEqual(tables.count, 2)
        let font = try XCTUnwrap(textView.font)
        let formattedFirst = MarkdownTableFormatter.format(tables[0], in: text, font: font)
        let formattedSecond = MarkdownTableFormatter.format(tables[1], in: text, font: font)
        for (selection, formatFirst, formatSecond) in [
            (NSRange(location: firstRange.location + 3, length: 0), true, false),
            (secondRange, false, true),
            (NSRange(location: firstRange.location, length: firstRange.length + 2), true, false),
            (NSRange(location: 0, length: 0), true, true),
            (text.range(of: "Between untouched"), true, true),
            (NSRange(location: text.length, length: 0), true, true),
            (NSRange(location: NSMaxRange(firstRange), length: 0), true, true),
            (NSRange(location: 0, length: text.length), true, true)
        ] {
            editor.text = source
            textView.setSelectedRange(selection)
            undo.removeAllActions()
            var changes = 0
            editor.onTextChanged = { changes += 1 }
            XCTAssertTrue(editor.canFormatMarkdownTable)
            editor.formatMarkdownTable()
            let expected = prefix + (formatFirst ? formattedFirst : first) + middle + (formatSecond ? formattedSecond : second) + suffix
            XCTAssertEqual(editor.text, expected, "\(selection)")
            XCTAssertEqual(changes, 1)
            XCTAssertEqual(undo.undoActionName, "Format Markdown Table")
            undo.undo()
            XCTAssertEqual(editor.text, source)
            XCTAssertFalse(undo.canUndo)
            undo.redo()
            XCTAssertEqual(editor.text, expected)
        }
        let partiallyFormatted = prefix + formattedFirst + middle + second + suffix
        editor.text = partiallyFormatted
        textView.setSelectedRange(NSRange(location: prefix.utf16.count + 3, length: 0))
        undo.removeAllActions()
        editor.formatMarkdownTable()
        XCTAssertEqual(editor.text, partiallyFormatted)
        XCTAssertFalse(undo.canUndo)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.formatMarkdownTable()
        XCTAssertEqual(editor.text, prefix + formattedFirst + middle + formattedSecond + suffix)
        undo.undo()
        XCTAssertEqual(editor.text, partiallyFormatted)
        editor.text = "ordinary text\n\nnot | a table"
        XCTAssertFalse(editor.canFormatMarkdownTable)
        undo.removeAllActions()
        editor.formatMarkdownTable()
        XCTAssertEqual(editor.text, "ordinary text\n\nnot | a table")
        XCTAssertFalse(undo.canUndo)
    }

    @MainActor
    func testEditorFormattingUndoAndRenderingPreserveNativeText() async throws {
        _ = NSApplication.shared
        let editor = EditorViewController()
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        defer { window.orderOut(nil) }
        editor.syntaxLanguage = .markdown
        let source = "| Name | Status |\n| :--- | ---: |\n| parser | ready |\n| renderer | ready |\n"
        editor.text = source
        let textView = try XCTUnwrap(findTextView(editor.view))
        window.makeFirstResponder(textView)
        let manager = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        let table = try XCTUnwrap(manager.markdownTables.tables.first)
        for _ in 0..<100 {
            if let font = textView.textStorage?.attribute(.font, at: table.rows[0].cells[0].location, effectiveRange: nil) as? NSFont,
               font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any] != nil,
               NSFontManager.shared.weight(of: font) > NSFontManager.shared.weight(of: EditorFontResolver.font(for: EditorSettings.currentFontID(), size: EditorSettings.currentFontSize())) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(editor.text, source)
        let header = try XCTUnwrap(textView.textStorage?.attribute(.font, at: table.rows[0].cells[0].location, effectiveRange: nil) as? NSFont)
        let body = try XCTUnwrap(textView.textStorage?.attribute(.font, at: table.rows[2].cells[0].location, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(NSFontManager.shared.weight(of: header), NSFontManager.shared.weight(of: body))
        XCTAssertEqual(header.pointSize, body.pointSize)
        let pipeColor = try XCTUnwrap(textView.textStorage?.attribute(.foregroundColor, at: table.rows[0].pipes[0], effectiveRange: nil) as? NSColor)
        XCTAssertLessThan(pipeColor.alphaComponent, 0.1)
        let separatorColor = try XCTUnwrap(textView.textStorage?.attribute(.foregroundColor, at: table.rows[1].cells[0].location, effectiveRange: nil) as? NSColor)
        XCTAssertGreaterThan(separatorColor.alphaComponent, 0)
        XCTAssertLessThanOrEqual(separatorColor.alphaComponent, pipeColor.alphaComponent)
        textView.setSelectedRange(NSRange(location: table.rows[2].cells[0].location, length: 0))
        XCTAssertTrue(editor.canFormatMarkdownTable)
        let undo = try XCTUnwrap(textView.undoManager)
        undo.removeAllActions()
        editor.formatMarkdownTable()
        let formatted = editor.text
        XCTAssertNotEqual(formatted, source)
        undo.undo()
        XCTAssertEqual(editor.text, source)
        undo.redo()
        XCTAssertEqual(editor.text, formatted)
        let formattedTable = try XCTUnwrap(manager.markdownTables.tables.first)
        textView.insertText("invalid", replacementRange: formattedTable.rows[1].cells[0])
        XCTAssertTrue(manager.markdownTables.tables.isEmpty)
        for _ in 0..<100 {
            let font = textView.textStorage?.attribute(.font, at: formattedTable.rows[0].cells[0].location, effectiveRange: nil) as? NSFont
            if font == body { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(textView.textStorage?.attribute(.font, at: formattedTable.rows[0].cells[0].location, effectiveRange: nil) as? NSFont, body)
        editor.text = formatted
        editor.syntaxLanguage = .plaintext
        XCTAssertTrue(manager.markdownTables.tables.isEmpty)
        XCTAssertFalse(editor.canFormatMarkdownTable)
        editor.formatMarkdownTable()
        XCTAssertEqual(editor.text, formatted)
    }

    @MainActor
    private func findTextView(_ view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { self.findTextView($0) }.first
    }
}
