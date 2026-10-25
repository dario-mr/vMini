import AppKit
import XCTest
@testable import vmini

@MainActor
final class SyntaxHighlightingPerformanceTests: XCTestCase {
    func testReleasePerformanceCorpus() throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh to measure the Release corpus")
        }

        let corpusDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("PerformanceCorpus", isDirectory: true)
        let cases: [(name: String, language: SyntaxLanguage, text: String, token: String, role: SyntaxColorRole)] = [
            ("token-dense-json", .json, try String(contentsOf: corpusDirectory.appendingPathComponent("TokenDense.json"), encoding: .utf8), "\"key\"", .propertyKey),
            ("multiline-bash", .bash, try String(contentsOf: corpusDirectory.appendingPathComponent("Multiline.sh"), encoding: .utf8), "$USER", .variable),
            ("large-markdown", .markdown, try String(contentsOf: corpusDirectory.appendingPathComponent("LargeMarkdown.md"), encoding: .utf8), "`inline code`", .inlineCode),
        ]

        for sample in cases {
            _ = highlightCorpusText(sample.text, language: sample.language)
            var durations: [Double] = []
            for iteration in 0..<6 {
                let start = DispatchTime.now().uptimeNanoseconds
                let output = highlightCorpusText(sample.text, language: sample.language)
                let duration = PerformanceBenchmark.elapsedMilliseconds(since: start)
                XCTAssertEqual(output.string, sample.text)
                XCTAssertEqual(output.length, (sample.text as NSString).length)
                let tokenLocation = (sample.text as NSString).range(of: sample.token).location
                XCTAssertNotEqual(tokenLocation, NSNotFound)
                assertColor(ThemeCatalog.palette(for: .default).syntaxTheme.color(for: sample.role), at: tokenLocation, in: output)
                if iteration > 0 { durations.append(duration) }
            }

            PerformanceBenchmark.emit(
                "full.\(sample.name)", classification: "warm-full-document",
                boundary: "highlight-call", inputUTF16Length: (sample.text as NSString).length,
                samples: durations
            )
        }
    }

    private func highlightCorpusText(_ text: String, language: SyntaxLanguage) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let baseFont = EditorFontResolver.font(for: .fallback, size: 13)
        let range = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.addAttribute(.font, value: baseFont, range: range)
        storage.addAttribute(.foregroundColor, value: theme.plainText, range: range)
        storage.removeAttribute(.backgroundColor, range: range)
        HighlighterRegistry.shared.highlighter(for: language).highlight(
            textStorage: storage,
            in: range,
            baseFont: baseFont,
            theme: theme,
            registry: HighlighterRegistry.shared
        )
        storage.endEditing()
        return storage
    }

    private func assertColor(_ expected: NSColor, at location: Int, in storage: NSTextStorage) {
        let actual = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertTrue(actual?.isEqual(expected) == true, "Expected \(expected), got \(String(describing: actual)) at UTF-16 offset \(location)")
    }
}
