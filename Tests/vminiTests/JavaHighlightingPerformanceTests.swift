import AppKit
import XCTest
@testable import vmini

@MainActor
final class JavaHighlightingPerformanceTests: XCTestCase {
    func testReleaseJavaHighlighting() async throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh to measure highlighting")
        }
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let font = EditorFontResolver.font(for: .fallback, size: 13)
        for methodCount in [100, 2_000] {
            let text = "class Example {\n" + (0..<methodCount).map {
                "    // Method \($0): Unicode 😀\n    String value\($0)() { return \"hello \($0)\"; }\n"
            }.joined() + "}\n"
            var fullSamples: [Double] = []
            for sample in 0..<6 {
                let storage = NSTextStorage(string: text)
                let start = DispatchTime.now().uptimeNanoseconds
                JavaSyntaxHighlighter().highlight(
                    textStorage: storage, in: nil, baseFont: font, theme: theme, registry: .shared
                )
                if sample > 0 { fullSamples.append(milliseconds(since: start)) }
                XCTAssertEqual(storage.string, text)
            }

            let storage = NSTextStorage(string: text)
            let controller = EditorSyntaxHighlightController(
                highlighterRegistry: .shared, textStorageProvider: { storage },
                syntaxThemeProvider: { theme }, baseFontProvider: { font }
            )
            controller.refresh(language: .java)
            let keyword = (text as NSString).range(of: "return", options: .backwards)
            try await waitForColor(theme.keyword, at: keyword.location, in: storage)
            var editSamples: [Double] = []
            for sample in 0..<21 {
                let replacement = sample.isMultiple(of: 2) ? "X" : ""
                let range = NSRange(location: NSMaxRange(keyword), length: replacement.isEmpty ? 1 : 0)
                let edit = SyntaxHighlightEditContext(
                    replacementRange: range, replacementString: replacement,
                    replacedText: (storage.string as NSString).substring(with: range)
                )
                let start = DispatchTime.now().uptimeNanoseconds
                storage.replaceCharacters(in: range, with: replacement)
                controller.handleProcessedEditing(
                    editedMask: .editedCharacters,
                    editedRange: NSRange(location: range.location, length: replacement.utf16.count),
                    language: .java, editContext: edit
                )
                try await waitForColor(
                    sample.isMultiple(of: 2) ? theme.plainText : theme.keyword,
                    at: keyword.location, in: storage
                )
                if sample > 0 { editSamples.append(milliseconds(since: start)) }
            }
            print(String(
                format: "PERF_JAVA utf16=%d full_median_ms=%.3f edit_median_ms=%.3f edit_p95_ms=%.3f",
                (text as NSString).length, median(fullSamples), median(editSamples),
                editSamples.sorted()[Int(ceil(Double(editSamples.count) * 0.95)) - 1]
            ))
        }
    }

    private func waitForColor(_ color: NSColor, at location: Int, in storage: NSTextStorage) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor != color {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                XCTFail("Highlighting did not finish")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 100_000)
        }
    }

    private func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func median(_ samples: [Double]) -> Double {
        samples.sorted()[samples.count / 2]
    }
}
