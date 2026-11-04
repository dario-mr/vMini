import AppKit
import XCTest
@testable import vmini

@MainActor
final class MarkdownTablePerformanceTests: XCTestCase {
    func testLargeMixedMarkdownEdits() async throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh to measure editing")
        }
        let id = "edit.large-document.mixed-markdown"
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let body = try String(contentsOf: PerformanceBenchmark.corpusDirectory.appendingPathComponent("LargeMarkdown.md"), encoding: .utf8)
        let text = "# Mixed document\n\n" + body + "\n\n"
            + "| Name | Status |\n| --- | --- |\n| parser | ready |\n| renderer | ready |\n\n"
            + "<https://example.com>\n\n<!--\nA | B\n--- | ---\nx | y\n-->\n\n"
            + "`mixed performance tail`\n"
        let tail = try PerformanceBenchmark.range(of: "`mixed performance tail`", in: text, scenarioID: id)
        let toggles = [
            try PerformanceBenchmark.markdownToggle("#", in: text, activeText: "#", inactiveText: "x",
                activeColor: theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha), theme: theme, scenarioID: id),
            PerformanceBenchmark.Toggle(range: NSRange(location: tail.location, length: 1), activeText: "`", inactiveText: "x",
                activeColor: theme.inlineCode, inactiveColor: theme.plainText, witnessOffset: 1, isActive: true),
        ]
        try await PerformanceBenchmark.runWarmScenario(id, text: text, language: .markdown, toggles: toggles)
    }

    func testLargeTableEditorInteractions() async throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh to measure editor drawing")
        }
        let originalDefaults = EditorSettings.userDefaults
        let suite = "vmini-table-performance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        EditorSettings.userDefaults = defaults
        defer {
            EditorSettings.userDefaults = originalDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        _ = NSApplication.shared
        let editor = EditorViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentViewController = editor
        defer { window.orderOut(nil) }
        editor.syntaxLanguage = .markdown
        let header = "| Item | Value   |\n| ---- | ------- |\n"
        let row = "| item | `value` |\n"
        let source = header + String(repeating: row, count: 5_000) + "\n# Editor benchmark tail\n"
        editor.text = source
        editor.view.layoutSubtreeIfNeeded()
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        window.makeFirstResponder(textView)
        let storage = try XCTUnwrap(editor.textStorage)
        let theme = ThemeManager.shared.syntaxTheme
        let tail = try PerformanceBenchmark.range(of: "# Editor benchmark tail", in: source, scenarioID: "editor.large-table")
        try await PerformanceBenchmark.waitForColor(
            theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha),
            at: tail.location, storage: storage, scenarioID: "editor.large-table", revision: 0, expectation: "initial highlighting")
        let viewport = NSRect(x: 0, y: 0, width: 700, height: 450)
        let bitmap = try XCTUnwrap(textView.bitmapImageRepForCachingDisplay(in: viewport))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        memset(pixels, 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
        textView.cacheDisplay(in: viewport, to: bitmap)
        XCTAssertTrue(UnsafeBufferPointer(start: pixels, count: bitmap.bytesPerRow * bitmap.pixelsHigh).contains { $0 != 255 },
                      "The editor must actually paint the viewport")
        let firstRow = (header as NSString).length
        var selectionSamples: [Double] = []
        for sample in 0..<(PerformanceBenchmark.warmSampleCount + 3) {
            let selection = NSRange(location: firstRow + (sample % 2) * (row as NSString).length + 2, length: 0)
            let start = DispatchTime.now().uptimeNanoseconds
            textView.setSelectedRange(selection)
            textView.cacheDisplay(in: viewport, to: bitmap)
            if sample >= 3 { selectionSamples.append(PerformanceBenchmark.elapsedMilliseconds(since: start)) }
            XCTAssertEqual(textView.selectedRange(), selection)
            XCTAssertEqual(storage.string, source)
        }
        PerformanceBenchmark.emit("editor.large-table.selection", classification: "warm-edit",
            boundary: "selection-to-viewport-rasterization", inputUTF16Length: (source as NSString).length,
            samples: selectionSamples, includeP95: true)

        let marker = (source as NSString).range(of: "`value`", options: .backwards)
        guard marker.location != NSNotFound else { throw PerformanceBenchmark.Failure.invalidRange("editor.large-table.typing", 0) }
        let manager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        let markerGlyphs = manager.glyphRange(forCharacterRange: marker, actualCharacterRange: nil)
        let markerRect = manager.boundingRect(forGlyphRange: markerGlyphs, in: container)
        let typingViewport = NSRect(x: 0, y: max(0, markerRect.minY - 200), width: viewport.width, height: viewport.height)
        textView.scrollRangeToVisible(marker)
        var typingSamples: [Double] = []
        var active = true
        for sample in 0..<(PerformanceBenchmark.warmSampleCount + 3) {
            let next = !active
            let replacement = next ? "`" : ""
            let start = DispatchTime.now().uptimeNanoseconds
            textView.insertText(replacement, replacementRange: NSRange(location: marker.location, length: active ? 1 : 0))
            try await PerformanceBenchmark.waitForChangedColor(next ? theme.inlineCode : theme.plainText,
                at: marker.location + (next ? 1 : 0), storage: storage, scenarioID: "editor.large-table.typing", revision: sample + 1,
                expectation: "unmodified cell text recolored by the latest edit")
            textView.cacheDisplay(in: typingViewport, to: bitmap)
            if sample >= 3 { typingSamples.append(PerformanceBenchmark.elapsedMilliseconds(since: start)) }
            XCTAssertEqual(storage.string, (source as NSString).replacingCharacters(
                in: NSRange(location: marker.location, length: 1), with: replacement))
            active = next
        }
        PerformanceBenchmark.emit("editor.large-table.typing", classification: "warm-edit",
            boundary: "edit-to-highlighted-viewport-rasterization", inputUTF16Length: (source as NSString).length,
            samples: typingSamples, includeP95: true)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }
}
