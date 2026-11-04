import AppKit
import XCTest
@testable import vmini

@MainActor
final class MarkdownTableColumnTests: XCTestCase {
    private let tableSource = "| A    | B    | C    |\n| ---- | ---- | ---- |\n| aaaa | 1    | aa   |\n| bbb  | 22   | ddd  |"
    private var currentEditor: EditorViewController?

    func testColumnPositionsComeFromNativePipeBoundsWithOptionalOuterPipes() throws {
        for (source, expected) in [(tableSource, Set(0...3)), ("A    | B\n---- | ----\naaaa | bbb", Set([1]))] {
            let (_, textView, manager) = try makeEditor(source)
            let table = try XCTUnwrap(manager.markdownTables.tables.first)
            let layout = try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager))
            XCTAssertEqual(Set(layout.columns.keys), expected)
            for row in layout.rows {
                for pipe in row.pipes {
                    let glyphs = manager.glyphRange(forCharacterRange: pipe.range, actualCharacterRange: nil)
                    let native = manager.boundingRect(forGlyphRange: glyphs, in: try XCTUnwrap(textView.textContainer))
                    XCTAssertEqual(pipe.x, native.midX)
                    XCTAssertEqual(layout.columns[pipe.column], native.midX)
                }
            }
        }
    }

    func testVerticalRulesAreContinuousAndOuterBoxUsesOuterPipes() throws {
        let source = "Intro\n\n" + tableSource
        let (editor, textView, manager) = try makeEditor(source)
        let table = try XCTUnwrap(manager.markdownTables.tables.first)
        let layout = try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager))
        let x = Int(try XCTUnwrap(layout.columns[1]))
        let normal = try render(manager)
        for y in (Int(layout.rows[0].rect.minY) + 2)..<(Int(try XCTUnwrap(layout.rows.last).rect.maxY) - 2) {
            let line = try XCTUnwrap(normal.colorAt(x: x, y: y)).brightnessComponent
            let background = try XCTUnwrap(normal.colorAt(x: x + 3, y: y)).brightnessComponent
            XCTAssertLessThan(line, background - 0.02)
        }
        let left = Int(floor(try XCTUnwrap(layout.columns[0]) - 0.5))
        let right = Int(ceil(try XCTUnwrap(layout.columns[3]) + 0.5)) - 1
        let row = layout.rows[2]
        let y = Int(row.rect.midY)
        for edge in [left, right] {
            XCTAssertLessThan(try XCTUnwrap(normal.colorAt(x: edge, y: y)).brightnessComponent, 0.85)
        }
        XCTAssertEqual(normal.colorAt(x: left - 1, y: y)?.brightnessComponent, 1)
        XCTAssertEqual(normal.colorAt(x: right + 1, y: y)?.brightnessComponent, 1)

        textView.setSelectedRange(NSRange(location: table.rows[2].cells[0].location, length: 0))
        let selected = try render(manager)
        XCTAssertEqual(try XCTUnwrap(selected.colorAt(x: x, y: y)).brightnessComponent,
                       try XCTUnwrap(selected.colorAt(x: x + 3, y: y)).brightnessComponent, accuracy: 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(selected.colorAt(x: left, y: y)).brightnessComponent, 0.95)
        XCTAssertGreaterThan(try XCTUnwrap(selected.colorAt(x: right, y: y)).brightnessComponent, 0.95)
        for pipe in table.rows[2].pipes {
            XCTAssertGreaterThan(try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: pipe, effectiveRange: nil) as? NSColor).alphaComponent, 0)
        }
        let otherY = Int(layout.rows[3].rect.midY)
        XCTAssertLessThan(try XCTUnwrap(selected.colorAt(x: x, y: otherY)).brightnessComponent,
                          try XCTUnwrap(selected.colorAt(x: x + 3, y: otherY)).brightnessComponent - 0.02)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let restored = try render(manager)
        XCTAssertEqual(restored.colorAt(x: x, y: y)?.brightnessComponent, normal.colorAt(x: x, y: y)?.brightnessComponent)
        XCTAssertEqual(editor.text, source)
        textView.needsDisplay = false
        _ = try render(manager)
        XCTAssertFalse(textView.needsDisplay)
    }

    func testResizingAndFontChangesReevaluateWhichPipesCanBeRendered() throws {
        let (editor, textView, manager) = try makeEditor("Intro\n\n" + tableSource)
        let table = try XCTUnwrap(manager.markdownTables.tables.first)
        let pipe = table.rows[2].pipes[1]
        XCTAssertEqual(try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: pipe, effectiveRange: nil) as? NSColor).alphaComponent, 0)
        let container = try XCTUnwrap(textView.textContainer)
        container.containerSize.width = 60
        _ = try render(manager)
        XCTAssertTrue(try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager)).columns.isEmpty)
        XCTAssertNil(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: pipe, effectiveRange: nil))
        container.containerSize.width = 600
        textView.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        _ = try render(manager)
        XCTAssertEqual(try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager)).columns.count, 4)
        XCTAssertEqual(try XCTUnwrap(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: pipe, effectiveRange: nil) as? NSColor).alphaComponent, 0)
        XCTAssertEqual(editor.text, "Intro\n\n" + tableSource)
    }

    func testMisalignedOuterPipesDoNotAddGutters() throws {
        for changedRow in ["| aaaa | 1    | aa  |", "| aaaa | 1    | aa    |", " | aaaa | 1    | aa   |"] {
            let source = "Intro\n\n" + tableSource.replacingOccurrences(of: "| aaaa | 1    | aa   |", with: changedRow)
            let (editor, textView, manager) = try makeEditor(source)
            let table = try XCTUnwrap(manager.markdownTables.tables.first)
            let layout = try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager))
            XCTAssertNil(layout.columns[3])
            let leftX = try XCTUnwrap(layout.rows.compactMap { $0.pipes.first?.x }.min())
            let rightX = try XCTUnwrap(layout.rows.compactMap { $0.pipes.last?.x }.max())
            XCTAssertEqual(layout.outerEdges[0], leftX)
            XCTAssertEqual(layout.outerEdges[3], rightX)
            let left = Int(floor(leftX - 0.5))
            let right = Int(ceil(rightX + 0.5)) - 1
            let bitmap = try render(manager)
            let y = Int(layout.rows[3].rect.midY)
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: right, y: y)).brightnessComponent, 0.85)
            XCTAssertEqual(bitmap.colorAt(x: right + 1, y: y)?.brightnessComponent, 1)
            XCTAssertEqual(bitmap.colorAt(x: left - 1, y: y)?.brightnessComponent, 1)
            for (index, row) in layout.rows.enumerated() where index != 1 {
                let pipe = try XCTUnwrap(row.pipes.last)
                let onEdge = abs(pipe.x - rightX) <= 0.5
                XCTAssertEqual(layout.renders(pipe), onEdge)
                let color = manager.temporaryAttribute(.foregroundColor, atCharacterIndex: pipe.range.location, effectiveRange: nil) as? NSColor
                if onEdge { XCTAssertEqual(try XCTUnwrap(color).alphaComponent, 0) }
                else { XCTAssertNil(color) }
            }
            textView.setSelectedRange(NSRange(location: table.rows[2].cells[0].location, length: 0))
            let selected = try render(manager)
            let selectedY = Int(layout.rows[2].rect.midY)
            let selectedColor = try XCTUnwrap(selected.colorAt(x: right, y: selectedY)).brightnessComponent
            if layout.renders(try XCTUnwrap(layout.rows[2].pipes.last)) {
                XCTAssertGreaterThan(selectedColor, 0.95)
            } else {
                XCTAssertLessThan(selectedColor, 0.85)
            }
            XCTAssertEqual(editor.text, source)
        }
    }

    func testTypingBelowTableDoesNotExtendDecorations() throws {
        let source = "Intro\n\n" + tableSource + "\n\n"
        let (editor, textView, manager) = try makeEditor(source)
        let table = try XCTUnwrap(manager.markdownTables.tables.first)
        for character in "plain text" {
            textView.insertText(String(character), replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
            XCTAssertEqual(manager.markdownTables.tables, [table])
        }
        let layout = try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager))
        let belowGlyphs = manager.glyphRange(forCharacterRange: NSRange(location: source.utf16.count, length: 1), actualCharacterRange: nil)
        let below = manager.lineFragmentRect(forGlyphAt: belowGlyphs.location, effectiveRange: nil)
        let bitmap = try render(manager)
        let x = Int(try XCTUnwrap(layout.columns[1]))
        XCTAssertEqual(bitmap.colorAt(x: x, y: Int(below.midY))?.brightnessComponent, 1)

        let newRow = "| new | row | cells |"
        textView.insertText(newRow, replacementRange: NSRange(location: source.utf16.count, length: "plain text".utf16.count))
        XCTAssertEqual(manager.markdownTables.tables, [table])
        textView.insertText("plain text", replacementRange: NSRange(location: source.utf16.count, length: newRow.utf16.count))
        XCTAssertEqual(manager.markdownTables.tables, [table])
        XCTAssertEqual(editor.text, source + "plain text")
    }

    func testMisalignedAndRaggedRowsKeepSourcePipes() throws {
        for source in ["| A | B |\n| --- | --- |\n| a | a much longer cell |", "| A | B |\n| --- | --- |\n| missing |"] {
            let (_, _, manager) = try makeEditor("Intro\n\n" + source)
            let table = try XCTUnwrap(manager.markdownTables.tables.first)
            let layout = try XCTUnwrap(MarkdownTableColumnLayout(table: table, layoutManager: manager))
            XCTAssertNil(layout.columns[1])
            let pipe = table.rows[0].pipes[1]
            _ = try render(manager)
            XCTAssertNil(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: pipe, effectiveRange: nil))
        }
    }

    func testEscapedAndInlineCodePipesRemainContent() throws {
        let source = "| A | B |\n| --- | --- |\n| a\\|b | `c\\|d` |"
        let table = try XCTUnwrap(MarkdownTableParser.parse(source as NSString).first)
        let formatted = "Intro\n\n" + MarkdownTableFormatter.format(table, in: source as NSString,
                           font: .monospacedSystemFont(ofSize: 14, weight: .regular))
        let (_, _, manager) = try makeEditor(formatted)
        let parsed = try XCTUnwrap(manager.markdownTables.tables.first)
        XCTAssertEqual(try XCTUnwrap(MarkdownTableColumnLayout(table: parsed, layoutManager: manager)).columns.count, 3)
        let escaped = (formatted as NSString).range(of: "\\|").location + 1
        let code = (formatted as NSString).range(of: "`c\\|d`").location + 3
        for location in [escaped, code] {
            XCTAssertNil(manager.temporaryAttribute(.foregroundColor, atCharacterIndex: location, effectiveRange: nil))
        }
        XCTAssertEqual(parsed.rows[2].pipes.count, 3)
    }

    func testSelectionReusesTableGeometryUntilLayoutChanges() throws {
        let (_, textView, manager) = try makeEditor("Intro\n\n" + tableSource)
        let table = try XCTUnwrap(manager.markdownTables.tables.first)
        let initial = manager.markdownTableLayouts.layout(for: table, layoutManager: manager)
        for row in table.rows {
            textView.setSelectedRange(NSRange(location: row.cells[0].location, length: 0))
            _ = try render(manager)
            XCTAssertTrue(manager.markdownTableLayouts.layout(for: table, layoutManager: manager) === initial)
        }
        let container = try XCTUnwrap(textView.textContainer)
        container.containerSize.width = 60
        let resized = manager.markdownTableLayouts.layout(for: table, layoutManager: manager)
        XCTAssertFalse(resized === initial)
        XCTAssertTrue(try XCTUnwrap(resized.columns).columns.isEmpty)
        textView.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        let changedFont = manager.markdownTableLayouts.layout(for: table, layoutManager: manager)
        XCTAssertFalse(changedFont === resized)
        textView.insertText("changed", replacementRange: table.rows[2].cells[0])
        let edited = try XCTUnwrap(manager.markdownTables.tables.first)
        XCTAssertFalse(manager.markdownTableLayouts.layout(for: edited, layoutManager: manager) === changedFont)
    }

    private func makeEditor(_ source: String) throws -> (EditorViewController, NSTextView, EditorSearchLayoutManager) {
        _ = NSApplication.shared
        let editor = EditorViewController()
        currentEditor = editor
        editor.syntaxLanguage = .markdown
        editor.text = source
        let textView = try XCTUnwrap(findTextView(editor.view))
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        let manager = try XCTUnwrap(textView.layoutManager as? EditorSearchLayoutManager)
        manager.outlineColor = .black
        MarkdownTableRendering.updateDelimiterVisibility(in: textView)
        _ = try render(manager)
        return (editor, textView, manager)
    }

    private func render(_ manager: NSLayoutManager) throws -> NSBitmapImageRep {
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: 0, length: manager.textStorage!.length), actualCharacterRange: nil)
        let image = NSImage(size: NSSize(width: 600, height: 400), flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            manager.drawBackground(forGlyphRange: glyphs, at: .zero)
            return true
        }
        return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
    }

    private func findTextView(_ view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { self.findTextView($0) }.first
    }

}
