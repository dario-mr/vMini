import AppKit
import XCTest
@testable import vmini

@MainActor
final class JavaHighlightingPerformanceTests: XCTestCase {
    func testReleaseJavaHighlighting() async throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh to measure the Release corpus")
        }

        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let font = EditorFontResolver.font(for: .fallback, size: 13)
        for methodCount in [100, 2_000] {
            let text = "class Example {\n" + (0..<methodCount).map {
                "    // Method \($0): Unicode 😀\n    String value\($0)() { return \"hello \($0)\"; }\n"
            }.joined() + "}\n"
            let returnRange = (text as NSString).range(of: "return")
            var fullSamples: [Double] = []
            for sample in 0..<6 {
                let storage = NSTextStorage(string: text)
                let start = DispatchTime.now().uptimeNanoseconds
                JavaSyntaxHighlighter().highlight(
                    textStorage: storage, in: nil, baseFont: font, theme: theme, registry: .shared
                )
                if sample > 0 { fullSamples.append(PerformanceBenchmark.elapsedMilliseconds(since: start)) }
                XCTAssertEqual(storage.string, text)
                let actualColor = storage.attribute(.foregroundColor, at: returnRange.location, effectiveRange: nil) as? NSColor
                XCTAssertTrue(actualColor?.isEqual(theme.keyword) == true, "Expected a Java return keyword color")
            }
            PerformanceBenchmark.emit(
                "full.java.\(methodCount)-methods", classification: "warm-full-document",
                boundary: "highlight-call", inputUTF16Length: (text as NSString).length,
                samples: fullSamples
            )

            let storage = NSTextStorage(string: text)
            let controller = PerformanceBenchmark.makeController(storage: storage, language: .java)
            let token = try PerformanceBenchmark.range(of: "return", in: text, scenarioID: "edit.java.\(methodCount)-methods")
            try await PerformanceBenchmark.waitForColor(
                theme.keyword, at: token.location, storage: storage,
                scenarioID: "edit.java.\(methodCount)-methods", revision: 0, expectation: "return keyword"
            )
            var samples: [Double] = []
            var isComment = false
            for sample in 0..<(PerformanceBenchmark.warmSampleCount + 3) {
                let nextIsComment = !isComment
                let replacement = nextIsComment ? "//" : "re"
                let expected = nextIsComment ? theme.comment : theme.keyword
                let start = DispatchTime.now().uptimeNanoseconds
                let submission = try PerformanceBenchmark.submit(
                    "edit.java.\(methodCount)-methods", revision: sample + 1,
                    range: NSRange(location: token.location, length: 2), replacement: replacement,
                    storage: storage, controller: controller, language: .java
                )
                try await PerformanceBenchmark.waitForChangedColor(
                    expected, at: token.location + 2, storage: storage,
                    scenarioID: "edit.java.\(methodCount)-methods", revision: sample + 1,
                    expectation: replacement == "//" ? "line comment" : "return keyword"
                )
                if sample >= 3 { samples.append(PerformanceBenchmark.elapsedMilliseconds(since: start)) }
                guard storage.string == submission.expectedText else {
                    throw PerformanceBenchmark.Failure.incorrectText("edit.java.\(methodCount)-methods", sample + 1)
                }
                isComment = nextIsComment
                let active = expected.isEqual(theme.keyword)
                try PerformanceBenchmark.check(
                    expected, at: token.location, in: storage,
                    scenarioID: "edit.java.\(methodCount)-methods", revision: sample + 1,
                    expectation: active ? "return keyword" : "line comment"
                )
            }
            PerformanceBenchmark.emit(
                "edit.java.\(methodCount)-methods", classification: "warm-edit",
                boundary: "edit-to-attribute", inputUTF16Length: (text as NSString).length,
                samples: samples, includeP95: true
            )
        }
    }
}
