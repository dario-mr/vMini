import AppKit
import XCTest
@testable import vmini

@MainActor
enum PerformanceBenchmark {
    static let warmSampleCount = 50
    static let timeoutNanoseconds: UInt64 = 5_000_000_000
    static let pollNanoseconds: UInt64 = 100_000

    struct Toggle {
        let range: NSRange
        let activeText: String
        let inactiveText: String
        let activeColor: NSColor
        let inactiveColor: NSColor
        let witnessOffset: Int
        var isActive: Bool
    }

    struct Submission {
        let expectedText: String
        let revision: Int
    }

    enum Failure: Error, LocalizedError {
        case invalidRange(String, Int)
        case unchangedWitness(String, Int)
        case timeout(String, Int, String)
        case incorrectText(String, Int)
        case incorrectColor(String, Int, Int, String)

        var errorDescription: String? {
            switch self {
            case let .unchangedWitness(scenario, revision):
                "\(scenario): witness already has the expected color before highlighting revision \(revision)"
            case let .invalidRange(scenario, revision):
                "\(scenario): invalid edit range at expected revision \(revision)"
            case let .timeout(scenario, revision, expectation):
                "\(scenario): timed out waiting for \(expectation) at expected revision \(revision) after 5000 ms"
            case let .incorrectText(scenario, revision):
                "\(scenario): final text was incorrect at expected revision \(revision)"
            case let .incorrectColor(scenario, revision, location, expectation):
                "\(scenario): expected \(expectation) at UTF-16 offset \(location), revision \(revision)"
            }
        }
    }

    static func emit(
        _ scenarioID: String,
        classification: String,
        boundary: String,
        inputUTF16Length: Int,
        samples: [Double],
        includeP95: Bool = false
    ) {
        let payload: [String: Any] = [
            "scenarioID": scenarioID,
            "classification": classification,
            "measurementBoundary": boundary,
            "unit": "milliseconds",
            "inputUTF16Length": inputUTF16Length,
            "samplesMilliseconds": samples,
            "includeP95": includeP95,
        ]
        write("VMINI_PERF_RESULT:", payload)
    }

    static func emitFailure(_ scenarioID: String, classification: String, _ error: Error) {
        write("VMINI_PERF_FAILURE:", [
            "scenarioID": scenarioID,
            "classification": classification,
            "failure": error.localizedDescription,
        ])
    }

    private static func write(_ prefix: String, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            XCTFail("Could not encode benchmark result")
            return
        }
        print(prefix + line)
    }

    static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func percentile95(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
    }

    static func makeController(storage: NSTextStorage, language: SyntaxLanguage) -> EditorSyntaxHighlightController {
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let font = EditorFontResolver.font(for: .fallback, size: 13)
        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: .shared,
            textStorageProvider: { storage },
            syntaxThemeProvider: { theme },
            baseFontProvider: { font }
        )
        controller.refresh(language: language)
        return controller
    }

    static func range(of needle: String, in text: String, scenarioID: String) throws -> NSRange {
        let range = (text as NSString).range(of: needle)
        guard range.location != NSNotFound else {
            throw Failure.invalidRange(scenarioID, 0)
        }
        return range
    }

    static func submit(
        _ scenarioID: String,
        revision: Int,
        range: NSRange,
        replacement: String,
        storage: NSTextStorage,
        controller: EditorSyntaxHighlightController,
        language: SyntaxLanguage
    ) throws -> Submission {
        let source = storage.string as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= source.length else {
            throw Failure.invalidRange(scenarioID, revision)
        }
        let replacedText = source.substring(with: range)
        let expectedText = source.replacingCharacters(in: range, with: replacement)
        let replacementRange = NSRange(location: range.location, length: (replacement as NSString).length)
        let edit = SyntaxHighlightEditContext(
            replacementRange: range,
            replacementString: replacement,
            replacedText: replacedText
        )
        storage.replaceCharacters(in: range, with: replacement)
        controller.handleProcessedEditing(
            editedMask: .editedCharacters,
            editedRange: replacementRange,
            language: language,
            editContext: edit
        )
        return Submission(expectedText: expectedText, revision: revision)
    }

    static func waitForColor(
        _ color: NSColor,
        at location: Int,
        storage: NSTextStorage,
        scenarioID: String,
        revision: Int,
        expectation: String
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while true {
            if location >= 0, location < storage.length,
               let actual = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor,
               actual.isEqual(color) {
                return
            }
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw Failure.timeout(scenarioID, revision, expectation)
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    static func waitForChangedColor(
        _ color: NSColor, at location: Int, storage: NSTextStorage,
        scenarioID: String, revision: Int, expectation: String
    ) async throws {
        // Inherited and undo-restored attributes are not evidence of a completed highlight.
        guard !matches(color, at: location, in: storage) else {
            throw Failure.unchangedWitness(scenarioID, revision)
        }
        try await waitForColor(color, at: location, storage: storage, scenarioID: scenarioID,
                               revision: revision, expectation: expectation)
    }

    static func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static func matches(_ color: NSColor, at location: Int, in storage: NSTextStorage) -> Bool {
        guard location >= 0, location < storage.length,
              let actual = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor else {
            return false
        }
        return actual.isEqual(color)
    }

    static func check(_ color: NSColor, at location: Int, in storage: NSTextStorage, scenarioID: String, revision: Int, expectation: String) throws {
        guard matches(color, at: location, in: storage) else {
            throw Failure.incorrectColor(scenarioID, revision, location, expectation)
        }
    }

    static func runWarmScenario(
        _ scenarioID: String,
        text: String,
        language: SyntaxLanguage = .markdown,
        toggles initialToggles: [Toggle]
    ) async throws {
        let inputLength = (text as NSString).length
        let storage = NSTextStorage(string: text)
        let controller = makeController(storage: storage, language: language)
        var toggles = initialToggles
        try await waitForToggles(toggles, storage: storage, scenarioID: scenarioID, revision: 0)

        var expectedText = text
        for index in 0..<3 {
            var toggle = toggles[index % toggles.count]
            let nextActive = !toggle.isActive
            let submission = try submit(
                scenarioID, revision: index + 1, range: toggle.range,
                replacement: nextActive ? toggle.activeText : toggle.inactiveText,
                storage: storage, controller: controller, language: language
            )
            try await waitForChangedColor(
                nextActive ? toggle.activeColor : toggle.inactiveColor,
                at: toggle.range.location + toggle.witnessOffset,
                storage: storage, scenarioID: scenarioID, revision: index + 1,
                expectation: nextActive ? "active token color" : "inactive token color"
            )
            expectedText = submission.expectedText
            toggle.isActive = nextActive
            toggles[index % toggles.count] = toggle
        }

        var samples: [Double] = []
        samples.reserveCapacity(warmSampleCount)
        for sample in 0..<warmSampleCount {
            let index = sample % toggles.count
            var toggle = toggles[index]
            let nextActive = !toggle.isActive
            let start = DispatchTime.now().uptimeNanoseconds
            let submission = try submit(
                scenarioID, revision: sample + 4, range: toggle.range,
                replacement: nextActive ? toggle.activeText : toggle.inactiveText,
                storage: storage, controller: controller, language: language
            )
            try await waitForChangedColor(
                nextActive ? toggle.activeColor : toggle.inactiveColor,
                at: toggle.range.location + toggle.witnessOffset,
                storage: storage, scenarioID: scenarioID, revision: sample + 4,
                expectation: nextActive ? "active token color" : "inactive token color"
            )
            samples.append(elapsedMilliseconds(since: start))
            expectedText = submission.expectedText
            toggle.isActive = nextActive
            toggles[index] = toggle

            guard storage.string == expectedText else {
                throw Failure.incorrectText(scenarioID, sample + 4)
            }
            try checkToggles(toggles, storage: storage, scenarioID: scenarioID, revision: sample + 4)
        }

        emit(scenarioID, classification: "warm-edit", boundary: "edit-to-attribute", inputUTF16Length: inputLength, samples: samples, includeP95: true)
    }

    static func waitForToggles(_ toggles: [Toggle], storage: NSTextStorage, scenarioID: String, revision: Int) async throws {
        for toggle in toggles {
            try await waitForColor(
                toggle.isActive ? toggle.activeColor : toggle.inactiveColor,
                at: toggle.range.location + toggle.witnessOffset,
                storage: storage, scenarioID: scenarioID, revision: revision,
                expectation: "initial token at UTF-16 offset \(toggle.range.location + toggle.witnessOffset)"
            )
        }
    }

    static func checkToggles(_ toggles: [Toggle], storage: NSTextStorage, scenarioID: String, revision: Int) throws {
        for toggle in toggles {
            try check(
                toggle.isActive ? toggle.activeColor : toggle.inactiveColor,
                at: toggle.range.location + toggle.witnessOffset,
                in: storage, scenarioID: scenarioID, revision: revision,
                expectation: toggle.isActive ? "active token color" : "inactive token color"
            )
        }
    }

    static func markdownToggle(
        _ token: String,
        in text: String,
        activeText: String,
        inactiveText: String,
        activeColor: NSColor,
        theme: SyntaxTheme,
        scenarioID: String,
        initiallyActive: Bool = true,
        witnessOffset: Int = 0
    ) throws -> Toggle {
        var range = try range(of: token, in: text, scenarioID: scenarioID)
        var activeText = activeText
        var inactiveText = inactiveText
        var activeColor = activeColor
        var witnessOffset = witnessOffset
        // Observe a character outside the replacement, which cannot inherit the desired color.
        switch token {
        case "#":
            activeColor = theme.headingText.blended(withFraction: 1, of: theme.headingMarker) ?? theme.headingText
            witnessOffset = 2
        case "1.":
            range.length = 1
            witnessOffset = 1
        case "`":
            witnessOffset = 1
        case "-":
            guard range.location > 0, (text as NSString).character(at: range.location - 1) == 10 else {
                throw Failure.invalidRange(scenarioID, 0)
            }
            range = NSRange(location: range.location - 1, length: 1)
            activeText = "\n"
            inactiveText = " "
            witnessOffset = 1
        default: break
        }
        return Toggle(
            range: range, activeText: activeText, inactiveText: inactiveText,
            activeColor: activeColor, inactiveColor: theme.plainText,
            witnessOffset: witnessOffset, isActive: initiallyActive
        )
    }
}
