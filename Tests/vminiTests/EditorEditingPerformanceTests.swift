import AppKit
import XCTest
@testable import vmini

@MainActor
private final class PerformanceEditorWindow: NSWindow {
    private let benchmarkUndoManager = UndoManager()

    override var undoManager: UndoManager? { benchmarkUndoManager }
}

@MainActor
final class EditorEditingPerformanceTests: XCTestCase {
    private let theme = ThemeCatalog.palette(for: .default).syntaxTheme

    func testInheritedColorCannotCompleteBenchmark() async throws {
        let storage = NSTextStorage(string: "old text")
        storage.addAttribute(.foregroundColor, value: theme.plainText, range: NSRange(location: 0, length: storage.length))
        storage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "new")
        do {
            try await PerformanceBenchmark.waitForChangedColor(
                theme.plainText, at: 0, storage: storage, scenarioID: "test", revision: 1,
                expectation: "fresh highlighting"
            )
            XCTFail("Inherited attributes must not count as completed highlighting")
        } catch PerformanceBenchmark.Failure.unchangedWitness {
            // The benchmark must reject this observation instead of recording a near-zero time.
        }
    }

    func testWarmEditingScenarios() async throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh to measure editing")
        }

        let scenarioID = "edit.plain-markdown"
        let text = "# Heading\n\nBullet context\n- Bullet\n1. Numbered\n`inline`\n"
        let scenarios: [(String, String, SyntaxLanguage, [PerformanceBenchmark.Toggle])] = [
            (scenarioID, text, .markdown, try toggles([
                ("#", "#", "x", theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha)),
                ("-", "-", "x", theme.listMarker),
                ("1.", "1", "x", theme.listMarker),
                ("`", "`", "x", theme.inlineCode),
            ], in: text, id: scenarioID)),
        ]

        var inputs = scenarios
        do {
            inputs += [
                try markdownSQLScenario(),
                try severalFenceScenario(),
                try largeMarkdownScenario(),
                try largeJavaScenario(),
                try unicodeScenario(),
            ]
        } catch {
            PerformanceBenchmark.emitFailure("edit.setup", classification: "warm-edit", error)
            XCTFail(error.localizedDescription)
            return
        }

        for (id, fixture, language, fixtureToggles) in inputs {
            do {
                try await PerformanceBenchmark.runWarmScenario(id, text: fixture, language: language, toggles: fixtureToggles)
            } catch {
                PerformanceBenchmark.emitFailure(id, classification: "warm-edit", error)
                XCTFail(error.localizedDescription)
            }
        }

        do {
            try await runRapidTyping()
        } catch {
            PerformanceBenchmark.emitFailure("edit.rapid-typing", classification: "warm-edit", error)
            XCTFail(error.localizedDescription)
        }
        do {
            try await runReplaceUndoRedo()
        } catch {
            PerformanceBenchmark.emitFailure("edit.replace-undo-redo", classification: "warm-edit", error)
            XCTFail(error.localizedDescription)
        }
    }

    func testColdMarkdownSQLInitialization() async throws {
        guard ProcessInfo.processInfo.environment["VMINI_RUN_PERFORMANCE_BENCHMARK"] == "1",
              ProcessInfo.processInfo.environment["VMINI_PERFORMANCE_SCENARIO"] == "cold" else {
            throw XCTSkip("Run scripts/benchmark-performance.sh in a fresh process for cold initialization")
        }

        let scenarioID = "cold.markdown-sql-first-highlight"
        let text = "# Cold\n```sql\nSELECT 1 FROM records\n```\n"
        let storage = NSTextStorage(string: text)
        let syntaxTheme = theme
        let font = EditorFontResolver.font(for: .fallback, size: 13)
        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: .shared,
            textStorageProvider: { storage },
            syntaxThemeProvider: { syntaxTheme },
            baseFontProvider: { font }
        )
        let select = (text as NSString).range(of: "SELECT")
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            controller.refresh(language: .markdown)
            try await PerformanceBenchmark.waitForColor(
                theme.keyword, at: select.location, storage: storage,
                scenarioID: scenarioID, revision: 1, expectation: "first SQL keyword highlight"
            )
            let samples = [PerformanceBenchmark.elapsedMilliseconds(since: start)]
            guard storage.string == text else {
                throw PerformanceBenchmark.Failure.incorrectText(scenarioID, 1)
            }
            try PerformanceBenchmark.check(theme.keyword, at: select.location, in: storage, scenarioID: scenarioID, revision: 1, expectation: "SQL keyword")
            PerformanceBenchmark.emit(
                scenarioID, classification: "cold-initialization", boundary: "first-highlight-to-attribute",
                inputUTF16Length: (text as NSString).length, samples: samples
            )
        } catch {
            PerformanceBenchmark.emitFailure(scenarioID, classification: "cold-initialization", error)
            XCTFail(error.localizedDescription)
        }
    }

    private func toggles(
        _ specs: [(token: String, active: String, inactive: String, color: NSColor)],
        in text: String,
        id: String
    ) throws -> [PerformanceBenchmark.Toggle] {
        try specs.map {
            try PerformanceBenchmark.markdownToggle(
                $0.token, in: text, activeText: $0.active, inactiveText: $0.inactive,
                activeColor: $0.color, theme: theme, scenarioID: id
            )
        }
    }

    private func markdownSQLScenario() throws -> (String, String, SyntaxLanguage, [PerformanceBenchmark.Toggle]) {
        let id = "edit.markdown-sql"
        let text = "# SQL edit\n```sql\nSELECT 1\nFROM records\nWHERE active = true;\n```\n\n1. item\n\nBullet context\n- Bullet\n"
        return (id, text, .markdown, [
            try PerformanceBenchmark.markdownToggle("#", in: text, activeText: "#", inactiveText: "x", activeColor: theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha), theme: theme, scenarioID: id),
            try PerformanceBenchmark.markdownToggle("1.", in: text, activeText: "1", inactiveText: "x", activeColor: theme.listMarker, theme: theme, scenarioID: id),
            PerformanceBenchmark.Toggle(range: try PerformanceBenchmark.range(of: "SELECT", in: text, scenarioID: id), activeText: "SELECT", inactiveText: "--SEL!", activeColor: theme.variable, inactiveColor: theme.comment, witnessOffset: 7, isActive: true),
        ])
    }

    private func severalFenceScenario() throws -> (String, String, SyntaxLanguage, [PerformanceBenchmark.Toggle]) {
        let id = "edit.several-fences"
        let text = "# Before\n```sql\nSELECT 1\n```\n\nBetween context\n- Between\n```java\nclass Example {}\n```\n```json\n{\"active\": true}\n```\n"
        let jsonValue = try PerformanceBenchmark.range(of: "true", in: text, scenarioID: id)
        let javaKeyword = try PerformanceBenchmark.range(of: "cl", in: text, scenarioID: id)
        return (id, text, .markdown, [
            try PerformanceBenchmark.markdownToggle("#", in: text, activeText: "#", inactiveText: "x", activeColor: theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha), theme: theme, scenarioID: id),
            try PerformanceBenchmark.markdownToggle("-", in: text, activeText: "-", inactiveText: "x", activeColor: theme.listMarker, theme: theme, scenarioID: id),
            PerformanceBenchmark.Toggle(range: try PerformanceBenchmark.range(of: "SELECT", in: text, scenarioID: id), activeText: "SELECT", inactiveText: "--SEL!", activeColor: theme.variable, inactiveColor: theme.comment, witnessOffset: 7, isActive: true),
            PerformanceBenchmark.Toggle(range: javaKeyword, activeText: "cl", inactiveText: "//", activeColor: theme.keyword, inactiveColor: theme.comment, witnessOffset: 2, isActive: true),
            PerformanceBenchmark.Toggle(range: jsonValue, activeText: "true", inactiveText: "\"x\" ", activeColor: theme.keyword, inactiveColor: theme.string, witnessOffset: 0, isActive: true),
        ])
    }

    private func largeMarkdownScenario() throws -> (String, String, SyntaxLanguage, [PerformanceBenchmark.Toggle]) {
        let id = "edit.large-document.markdown"
        let body = try markdownCorpus()
        let text = "# Performance head\n" + body + "\n\n`performance tail`\n"
        let tail = (text as NSString).range(of: "`performance tail`")
        let tailMarker = NSRange(location: tail.location, length: 1)
        let headingColor = theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha)
        return (id, text, .markdown, [
            try PerformanceBenchmark.markdownToggle("#", in: text, activeText: "#", inactiveText: "x", activeColor: headingColor, theme: theme, scenarioID: id),
            PerformanceBenchmark.Toggle(range: tailMarker, activeText: "`", inactiveText: "x", activeColor: theme.inlineCode, inactiveColor: theme.plainText, witnessOffset: 1, isActive: true),
        ])
    }

    private func largeJavaScenario() throws -> (String, String, SyntaxLanguage, [PerformanceBenchmark.Toggle]) {
        let id = "edit.large-document.java"
        let text = "class Example {\n" + (0..<2_000).map {
            "    String value\($0)() { return \"hello \($0)\"; }\n"
        }.joined() + "}\n"
        return (id, text, .java, [
            try javaToggle("cl", in: text, id: id),
            try javaToggle("re", in: text, id: id, last: true),
        ])
    }

    private func javaToggle(_ token: String, in text: String, id: String, last: Bool = false) throws -> PerformanceBenchmark.Toggle {
        let source = text as NSString
        let range = source.range(of: token, options: last ? .backwards : [])
        guard range.location != NSNotFound else { throw PerformanceBenchmark.Failure.invalidRange(id, 0) }
        return PerformanceBenchmark.Toggle(
            range: range,
            activeText: token,
            inactiveText: "//",
            activeColor: theme.keyword,
            inactiveColor: theme.comment,
            witnessOffset: 2,
            isActive: true
        )
    }

    private func rapidTypingScenario() throws -> (String, String, SyntaxLanguage, [PerformanceBenchmark.Toggle]) {
        let id = "edit.rapid-typing"
        let source = try markdownCorpus() as NSString
        let chunkEnd = source.lineRange(for: NSRange(location: min(20_000, source.length), length: 0)).location
        let chunk = source.substring(to: chunkEnd)
        let text = "# Burst heading\n\nBullet context\n- Burst bullet\n`burst code`\n" + String(repeating: chunk, count: 2)
        return (id, text, .markdown, try toggles([
            ("#", "#", "x", theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha)),
            ("-", "-", "x", theme.listMarker),
            ("`", "`", "x", theme.inlineCode),
        ], in: text, id: id))
    }

    private func markdownCorpus() throws -> String {
        let corpus = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("PerformanceCorpus/LargeMarkdown.md")
        return try String(contentsOf: corpus, encoding: .utf8)
    }

    private func unicodeScenario() throws -> (String, String, SyntaxLanguage, [PerformanceBenchmark.Toggle]) {
        let id = "edit.unicode-incomplete-syntax"
        let text = "# 😀 Unicode\n\n```sql\nSELECT 'word';\n--unfinished comment\n"
        let marker = try PerformanceBenchmark.range(of: "--", in: text, scenarioID: id)
        guard marker.location > (text as NSString).range(of: "😀").location + 1 else {
            throw PerformanceBenchmark.Failure.invalidRange(id, 0)
        }
        return (id, text, .markdown, [
            try PerformanceBenchmark.markdownToggle("#", in: text, activeText: "#", inactiveText: "x", activeColor: theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha), theme: theme, scenarioID: id),
            PerformanceBenchmark.Toggle(range: try PerformanceBenchmark.range(of: "'w", in: text, scenarioID: id), activeText: "'w", inactiveText: "--", activeColor: theme.string, inactiveColor: theme.comment, witnessOffset: 2, isActive: true),
            PerformanceBenchmark.Toggle(range: marker, activeText: "--", inactiveText: "  ", activeColor: theme.comment, inactiveColor: theme.plainText, witnessOffset: 2, isActive: true),
        ])
    }

    private func runRapidTyping() async throws {
        let (id, text, language, initialToggles) = try rapidTypingScenario()
        let storage = NSTextStorage(string: text)
        let controller = PerformanceBenchmark.makeController(storage: storage, language: language)
        var toggles = initialToggles
        try await PerformanceBenchmark.waitForToggles(toggles, storage: storage, scenarioID: id, revision: 0)
        var samples: [Double] = []
        var expectedText = text

        for sample in 0..<(PerformanceBenchmark.warmSampleCount + 3) {
            for index in 0..<2 {
                var toggle = toggles[index]
                let nextActive = !toggle.isActive
                let submission = try PerformanceBenchmark.submit(
                    id, revision: sample * 3 + index + 1, range: toggle.range,
                    replacement: nextActive ? toggle.activeText : toggle.inactiveText,
                    storage: storage, controller: controller, language: language
                )
                expectedText = submission.expectedText
                toggle.isActive = nextActive
                toggles[index] = toggle
                if index == 0 {
                    await Task.yield()
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
            }

            var finalToggle = toggles[2]
            let nextActive = !finalToggle.isActive
            let revision = sample * 3 + 3
            let start = DispatchTime.now().uptimeNanoseconds
            let submission = try PerformanceBenchmark.submit(
                id, revision: revision, range: finalToggle.range,
                replacement: nextActive ? finalToggle.activeText : finalToggle.inactiveText,
                storage: storage, controller: controller, language: language
            )
            try await PerformanceBenchmark.waitForChangedColor(
                nextActive ? finalToggle.activeColor : finalToggle.inactiveColor,
                at: finalToggle.range.location + finalToggle.witnessOffset,
                storage: storage, scenarioID: id, revision: revision,
                expectation: "final burst revision token color"
            )
            if sample >= 3 { samples.append(PerformanceBenchmark.elapsedMilliseconds(since: start)) }
            expectedText = submission.expectedText
            finalToggle.isActive = nextActive
            toggles[2] = finalToggle
            guard storage.string == expectedText else { throw PerformanceBenchmark.Failure.incorrectText(id, revision) }
            try PerformanceBenchmark.checkToggles(toggles, storage: storage, scenarioID: id, revision: revision)
        }

        PerformanceBenchmark.emit(id, classification: "warm-edit", boundary: "final-edit-to-final-revision-attributes", inputUTF16Length: (text as NSString).length, samples: samples, includeP95: true)
    }

    private func runReplaceUndoRedo() async throws {
        let id = "edit.replace-undo-redo"
        let editor = EditorViewController()
        editor.syntaxLanguage = .markdown
        let prefix = "before\n"
        let fence = "```sql\nSELECT 1\n"
        let suffix = "SELECT 2\n"
        let base = prefix + fence + suffix
        editor.text = base
        let window = PerformanceEditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        window.contentViewController = editor
        let storage = try XCTUnwrap(editor.textStorage)
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        let undoManager = try XCTUnwrap(textView.undoManager, "Editor text view must provide undo")
        undoManager.groupsByEvent = false
        var previousActive = true
        var currentRegion = fence
        var replaceSamples: [Double] = []
        var undoSamples: [Double] = []
        var redoSamples: [Double] = []
        try await PerformanceBenchmark.waitForColor(
            theme.keyword, at: (prefix + fence as NSString).length, storage: storage,
            scenarioID: id, revision: 0, expectation: "SQL suffix before replacement"
        )

        for sample in 0..<(PerformanceBenchmark.warmSampleCount + 3) {
            let nextActive = !previousActive
            let replacement = nextActive ? fence : "\n"
            let originalText = prefix + currentRegion + suffix
            let replacedText = prefix + replacement + suffix
            let selection = NSRange(location: (prefix as NSString).length, length: (currentRegion as NSString).length)
            let originalWitness = (prefix + currentRegion as NSString).length
            let replacementWitness = (prefix + replacement as NSString).length
            textView.setSelectedRange(selection)
            textView.breakUndoCoalescing()
            undoManager.beginUndoGrouping()
            let startReplace = DispatchTime.now().uptimeNanoseconds
            textView.insertText(replacement, replacementRange: selection)
            undoManager.endUndoGrouping()
            try await PerformanceBenchmark.waitForChangedColor(
                nextActive ? theme.keyword : theme.plainText, at: replacementWitness,
                storage: storage, scenarioID: id, revision: sample * 3 + 1,
                expectation: "unmodified suffix after selection replacement"
            )
            if sample >= 3 { replaceSamples.append(PerformanceBenchmark.elapsedMilliseconds(since: startReplace)) }
            guard storage.string == replacedText else {
                throw PerformanceBenchmark.Failure.incorrectText(id, sample * 3 + 1)
            }

            let startUndo = DispatchTime.now().uptimeNanoseconds
            undoManager.undo()
            try await PerformanceBenchmark.waitForChangedColor(
                previousActive ? theme.keyword : theme.plainText, at: originalWitness,
                storage: storage, scenarioID: id, revision: sample * 3 + 2,
                expectation: "unmodified suffix after undo"
            )
            if sample >= 3 { undoSamples.append(PerformanceBenchmark.elapsedMilliseconds(since: startUndo)) }
            guard storage.string == originalText else {
                throw PerformanceBenchmark.Failure.incorrectText(id, sample * 3 + 2)
            }

            let startRedo = DispatchTime.now().uptimeNanoseconds
            undoManager.redo()
            try await PerformanceBenchmark.waitForChangedColor(
                nextActive ? theme.keyword : theme.plainText, at: replacementWitness,
                storage: storage, scenarioID: id, revision: sample * 3 + 3,
                expectation: "unmodified suffix after redo"
            )
            if sample >= 3 { redoSamples.append(PerformanceBenchmark.elapsedMilliseconds(since: startRedo)) }
            guard storage.string == replacedText else {
                throw PerformanceBenchmark.Failure.incorrectText(id, sample * 3 + 3)
            }
            previousActive = nextActive
            currentRegion = replacement
        }

        let inputLength = (base as NSString).length
        PerformanceBenchmark.emit("edit.replace-undo-redo.replace", classification: "warm-edit", boundary: "edit-to-attribute", inputUTF16Length: inputLength, samples: replaceSamples, includeP95: true)
        PerformanceBenchmark.emit("edit.replace-undo-redo.undo", classification: "warm-edit", boundary: "undo-to-attribute", inputUTF16Length: inputLength, samples: undoSamples, includeP95: true)
        PerformanceBenchmark.emit("edit.replace-undo-redo.redo", classification: "warm-edit", boundary: "redo-to-attribute", inputUTF16Length: inputLength, samples: redoSamples, includeP95: true)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let textView = findTextView(in: subview) { return textView }
        }
        return nil
    }
}
