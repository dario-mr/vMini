import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import vmini

@MainActor
private final class RecordingSyntaxHighlighter: SyntaxHighlighter {
    let language: SyntaxLanguage = .plaintext
    private(set) var ranges: [NSRange] = []

    func clear() {
        ranges.removeAll()
    }

    func expandedHighlightRange(
        for editedRange: NSRange,
        editContext: SyntaxHighlightEditContext?,
        in text: NSString
    ) -> NSRange {
        editedRange
    }

    func highlight(
        textStorage: NSTextStorage,
        in range: NSRange?,
        baseFont: NSFont,
        theme: SyntaxTheme,
        registry: HighlighterRegistry
    ) {
        ranges.append(range ?? NSRange(location: 0, length: textStorage.length))
    }
}

@available(macOS 14.0, *)
@MainActor
final class SyntaxHighlightingTests: XCTestCase {
    func testLanguageResolverRecognizesMarkdownExtensions() {
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/notes.md"), typeIdentifier: nil),
            .markdown
        )
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/notes.markdown"), typeIdentifier: nil),
            .markdown
        )
    }

    func testLanguageResolverRecognizesJSONExtensions() {
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/data.json"), typeIdentifier: UTType.json.identifier),
            .json
        )
    }

    func testLanguageResolverRecognizesYAMLExtensions() {
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/config.yaml"), typeIdentifier: UTType.text.identifier),
            .yaml
        )
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/config.yml"), typeIdentifier: UTType.text.identifier),
            .yaml
        )
    }

    func testLanguageResolverRecognizesShellFilesAndShebangs() {
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/script.sh"), typeIdentifier: UTType.plainText.identifier),
            .bash
        )
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/.zshenv"), typeIdentifier: UTType.plainText.identifier),
            .bash
        )
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(
                fileURL: URL(fileURLWithPath: "/tmp/config"),
                typeIdentifier: UTType.text.identifier,
                content: "#!/usr/bin/env bash\nexport PATH=/tmp"
            ),
            .sshconfig
        )
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(
                fileURL: URL(fileURLWithPath: "/tmp/config"),
                typeIdentifier: UTType.text.identifier,
                content: "plain text"
            ),
            .sshconfig
        )
    }

    func testLanguageResolverRecognizesShellFenceInfoStrings() {
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("sh"), .bash)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("bash"), .bash)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("zsh"), .bash)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("shell"), .bash)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("json"), .json)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("yaml"), .yaml)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("yml"), .yaml)
    }

    func testLanguageResolverDefaultsOtherTextFilesToPlaintext() {
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/notes.txt"), typeIdentifier: UTType.plainText.identifier),
            .plaintext
        )
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/config"), typeIdentifier: UTType.text.identifier),
            .sshconfig
        )
    }

    func testMarkdownHighlighterStylesCoreMarkdownTokens() throws {
        let text = """
        # Title
        ## Subtitle
        ### Section
        - item
        1. ordered
        > quote
        `code`
        [docs](https://example.com)
        *em*
        **strong**
        ---
        ```sh
        echo hi
        ```
        """

        let storage = makeHighlightedStorage(text, language: .markdown)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString
        let h1Color = theme.headingMarker
        let h2Color = theme.headingText.blended(withFraction: 0.5, of: theme.headingMarker) ?? theme.headingText

        assertColor(theme.headingMarker, at: nsText.range(of: "#").location, in: storage)
        assertColor(h1Color, at: nsText.range(of: "Title").location, in: storage)
        assertBoldFont(at: nsText.range(of: "#").location, in: storage)
        assertBoldFont(at: nsText.range(of: "Title").location, in: storage)
        assertColor(h2Color, at: nsText.range(of: "Subtitle").location, in: storage)
        assertColor(theme.headingText, at: nsText.range(of: "Section").location, in: storage)
        assertColor(theme.listMarker, at: nsText.range(of: "- item").location, in: storage)
        assertColor(theme.listMarker, at: nsText.range(of: "1. ordered").location, in: storage)
        assertColor(theme.blockquoteMarker, at: nsText.range(of: "> quote").location, in: storage)
        assertColor(theme.inlineCode, at: nsText.range(of: "`code`").location + 1, in: storage)
        assertColor(theme.linkText, at: nsText.range(of: "[docs]").location + 1, in: storage)
        assertColor(theme.linkURL, at: nsText.range(of: "(https://example.com)").location + 1, in: storage)
        assertColor(theme.emphasisMarker, at: nsText.range(of: "*em*").location, in: storage)
        assertColor(theme.emphasisMarker, at: nsText.range(of: "**strong**").location, in: storage)
        assertColor(theme.thematicBreak, at: nsText.range(of: "---").location, in: storage)
        assertColor(theme.codeFence, at: nsText.range(of: "```sh").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "echo hi").location, in: storage)
        assertBackgroundColor(theme.codeBlockBackground, at: nsText.range(of: "echo hi").location, in: storage)
    }

    func testMarkdownHighlighterStylesStandaloneOrderedListMarkers() {
        let text = """
        1.
        2.
        3.
        """

        let storage = makeHighlightedStorage(text, language: .markdown)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.listMarker, at: nsText.range(of: "1.").location, in: storage)
        assertColor(theme.listMarker, at: nsText.range(of: "2.").location, in: storage)
        assertColor(theme.listMarker, at: nsText.range(of: "3.").location, in: storage)
    }

    func testMarkdownHighlighterUsesLocalRangeForPlainTextEdits() {
        let text = "one\ntwo\nthree\nfour\nfive\n" as NSString
        let editedRange = text.range(of: "three")
        let editContext = SyntaxHighlightEditContext(
            replacementRange: editedRange,
            replacementString: "THREE",
            replacedText: "three"
        )

        let range = MarkdownSyntaxHighlighter().expandedHighlightRange(
            for: editedRange,
            editContext: editContext,
            in: text
        )

        XCTAssertLessThan(range.length, text.length)
        XCTAssertTrue(range.intersects(editedRange))
    }

    func testMarkdownHighlighterUsesFullRangeForFenceEdits() {
        let text = "one\ntwo\n```sh\necho hi\n```\nfive\n" as NSString
        let editedRange = text.range(of: "```sh")
        let editContext = SyntaxHighlightEditContext(
            replacementRange: editedRange,
            replacementString: "```bash",
            replacedText: "```sh"
        )

        let range = MarkdownSyntaxHighlighter().expandedHighlightRange(
            for: editedRange,
            editContext: editContext,
            in: text
        )

        XCTAssertEqual(range, NSRange(location: 0, length: text.length))
    }

    func testMarkdownFenceCacheKeepsPlainEditsLocalAndShiftsUnicodeRanges() throws {
        let highlighter = MarkdownSyntaxHighlighter()
        let source = (0..<2_000).map { "paragraph \($0)" }.joined(separator: "\n")
            + "\n```sh\necho hi\n```\n"
        let originalText = source as NSString
        let cache = highlighter.makeFenceCache(in: originalText)
        let replacedRange = originalText.range(of: "paragraph 1000")
        let replacement = "paragraph 😀 changed"
        let editContext = SyntaxHighlightEditContext(
            replacementRange: replacedRange,
            replacementString: replacement,
            replacedText: originalText.substring(with: replacedRange)
        )
        let updatedText = originalText.replacingCharacters(in: replacedRange, with: replacement) as NSString

        let update = try XCTUnwrap(highlighter.updateFenceCache(cache, editContext: editContext, in: updatedText))

        XCTAssertEqual(update.rescannedLineCount, 0)
        XCTAssertLessThan(update.highlightRange.length, 100)
        XCTAssertEqual(update.cache.blocks, highlighter.makeFenceCache(in: updatedText).blocks)
    }

    func testMarkdownFenceCacheRescansUntilFenceStateMatchesAndReusesSuffix() throws {
        let highlighter = MarkdownSyntaxHighlighter()
        let source = (0..<1_000).map { "paragraph \($0)" }.joined(separator: "\n")
            + "\nplaceholder\n"
            + (1_000..<2_000).map { "paragraph \($0)" }.joined(separator: "\n")
            + "\n```json\n{\"kept\": true}\n```\n"
        let originalText = source as NSString
        let cache = highlighter.makeFenceCache(in: originalText)
        let replacedRange = originalText.range(of: "placeholder")
        let replacement = "```sh\necho hi\n```"
        let editContext = SyntaxHighlightEditContext(
            replacementRange: replacedRange,
            replacementString: replacement,
            replacedText: "placeholder"
        )
        let updatedText = originalText.replacingCharacters(in: replacedRange, with: replacement) as NSString

        let update = try XCTUnwrap(highlighter.updateFenceCache(cache, editContext: editContext, in: updatedText))

        XCTAssertGreaterThan(update.rescannedLineCount, 0)
        XCTAssertLessThan(update.rescannedLineCount, 10)
        XCTAssertLessThan(update.highlightRange.length, 100)
        XCTAssertEqual(update.cache.blocks, highlighter.makeFenceCache(in: updatedText).blocks)
    }

    func testFullHighlightRequestSurvivesEditsAndPendingRangesTrackOffsets() async throws {
        let highlighter = RecordingSyntaxHighlighter()
        let storage = NSTextStorage(string: "abcdefghij")
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let baseFont = EditorFontResolver.font(for: .fallback, size: 13)
        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: HighlighterRegistry(highlighters: [highlighter]),
            textStorageProvider: { storage },
            syntaxThemeProvider: { theme },
            baseFontProvider: { baseFont }
        )

        controller.refresh(language: .plaintext)
        applyEdit("X", at: 9, in: storage, controller: controller, language: .plaintext)
        try await waitForCondition { highlighter.ranges.count == 1 }
        XCTAssertEqual(highlighter.ranges[0], NSRange(location: 0, length: storage.length))

        highlighter.clear()
        applyEdit("Y", at: 9, in: storage, controller: controller, language: .plaintext)
        applyEdit("Z", at: 1, in: storage, controller: controller, language: .plaintext)
        try await waitForCondition { highlighter.ranges.count == 1 }
        XCTAssertEqual(highlighter.ranges[0], NSRange(location: 1, length: 10))

        highlighter.clear()
        applyEdit("Q", at: 11, in: storage, controller: controller, language: .plaintext)
        applyEdit(
            "",
            replacing: NSRange(location: 1, length: 3),
            in: storage,
            controller: controller,
            language: .plaintext
        )
        try await waitForCondition { highlighter.ranges.count == 1 }
        XCTAssertEqual(highlighter.ranges[0], NSRange(location: 1, length: 8))
    }

    func testMarkdownIncrementalStylesMatchFreshHighlightAfterRapidEditsAndUndo() async throws {
        let initialText = "Before\n# Heading\n```sh\necho old\n```\nAfter **strong**\n"
        let storage = unhighlightedStorage(initialText)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let baseFont = EditorFontResolver.font(for: .fallback, size: 13)
        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: .shared,
            textStorageProvider: { storage },
            syntaxThemeProvider: { theme },
            baseFontProvider: { baseFont }
        )
        controller.refresh(language: .markdown)
        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }

        let before = storage.string as NSString
        applyEdit("Prior 😀", replacing: before.range(of: "Before"), in: storage, controller: controller)
        let withPrefix = storage.string as NSString
        applyEdit("> ", at: withPrefix.range(of: "After").location, in: storage, controller: controller)
        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }

        let withQuote = storage.string as NSString
        let quoteRange = withQuote.range(of: "> After")
        applyEdit("", replacing: NSRange(location: quoteRange.location, length: 2), in: storage, controller: controller)
        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }

        let beforeCodeEdit = storage.string as NSString
        applyEdit("new", replacing: beforeCodeEdit.range(of: "old"), in: storage, controller: controller)
        let withoutClose = storage.string as NSString
        applyEdit("", replacing: withoutClose.range(of: "```", options: .backwards), in: storage, controller: controller)
        let openFenceText = storage.string as NSString
        applyEdit("```\n", replacing: openFenceText.range(of: "After"), in: storage, controller: controller)

        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }

        let editedText = storage.string as NSString
        applyEdit("Before", replacing: editedText.range(of: "Prior 😀"), in: storage, controller: controller)
        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }
    }

    func testTypingInMarkdownHeadingUsesAdjacentSyntaxAttributesImmediately() {
        let text = "## Title"
        let storage = makeHighlightedStorage(text, language: .markdown)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let baseFont = EditorFontResolver.font(for: .fallback, size: 13)
        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: .shared,
            textStorageProvider: { storage },
            syntaxThemeProvider: { theme },
            baseFontProvider: { baseFont }
        )
        let insertionLocation = storage.length
        let insertedRange = NSRange(location: insertionLocation, length: 1)

        storage.replaceCharacters(in: NSRange(location: insertionLocation, length: 0), with: "a")
        storage.applyForegroundColor(theme.plainText, range: insertedRange)
        controller.handleProcessedEditing(
            editedMask: [.editedCharacters],
            editedRange: insertedRange,
            language: .markdown,
            editContext: SyntaxHighlightEditContext(
                replacementRange: NSRange(location: insertionLocation, length: 0),
                replacementString: "a",
                replacedText: ""
            )
        )

        let expectedColor = theme.headingText.blended(withFraction: 0.5, of: theme.headingMarker) ?? theme.headingText
        assertColor(expectedColor, at: insertionLocation, in: storage)
    }

    func testMarkdownIncrementalHighlightingClearsBackgroundAfterClosingFence() async throws {
        let initialText = """
        ```sh
        export hello

        {"name": "adl-fusion"}
        aaa
        """
        let updatedText = """
        ```sh
        export hello
        ```

        {"name": "adl-fusion"}
        aaa
        """

        let storage = NSTextStorage(string: initialText)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let baseFont = EditorFontResolver.font(for: .fallback, size: 13)
        let initialRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.foregroundColor, value: theme.plainText, range: initialRange)
        storage.addAttribute(.font, value: baseFont, range: initialRange)

        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: .shared,
            textStorageProvider: { storage },
            syntaxThemeProvider: { theme },
            baseFontProvider: { baseFont }
        )

        controller.refresh(language: .markdown)
        let initialNSString = initialText as NSString
        let jsonInInitialText = initialNSString.range(of: "{\"name\": \"adl-fusion\"}").location
        try await waitForCondition {
            (storage.attribute(.backgroundColor, at: jsonInInitialText, effectiveRange: nil) as? NSColor)?
                .isEqual(theme.codeBlockBackground) == true
        }

        let insertionLocation = (storage.string as NSString).range(of: "\n\n{").location + 1
        applyEdit("```\n", at: insertionLocation, in: storage, controller: controller)
        XCTAssertEqual(storage.string, updatedText)

        let jsonLocation = (storage.string as NSString).range(of: "{\"name\": \"adl-fusion\"}").location
        try await waitForCondition {
            storage.attribute(.backgroundColor, at: jsonLocation, effectiveRange: nil) == nil
                && self.highlightingMatchesFresh(storage, language: .markdown)
        }

        XCTAssertNil(storage.attribute(.backgroundColor, at: jsonLocation, effectiveRange: nil))
        assertColor(theme.plainText, at: (storage.string as NSString).range(of: "aaa").location, in: storage)
    }

    func testBashHighlighterStylesCoreShellTokens() {
        let text = """
        # comment
        if [ \"$HOME\" = \"foo\" ]; then
          export PATH=$(pwd)
          echo '$USER'
          git remote -v
          ssh -T git@github-personal
          git config --global user.email
          ssh-add --apple-use-keychain ~/.ssh/macbookpro
        fi
        """

        let storage = makeHighlightedStorage(text, language: .bash)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.comment, at: nsText.range(of: "# comment").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "if").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: "[").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "$HOME").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "\"foo\"").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "export").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "$(pwd)").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "'$USER'").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "git remote -v").location, in: storage)
        assertColor(theme.option, at: nsText.range(of: "-v").location, in: storage)
        assertColor(theme.option, at: nsText.range(of: "-T").location, in: storage)
        assertColor(theme.option, at: nsText.range(of: "--global").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "ssh-add --apple-use-keychain").location, in: storage)
        assertColor(theme.option, at: nsText.range(of: "--apple-use-keychain").location, in: storage)
    }

    func testBashMultilineRangeCacheTracksOrdinaryUnicodeEdits() throws {
        let highlighter = BashSyntaxHighlighter()
        let original = "echo done\nprintf \"first\nmiddle\nlast\"\necho end"
        let originalNSString = original as NSString
        var ranges = highlighter.multilineTokenRanges(in: original)
        XCTAssertEqual(ranges, [originalNSString.range(of: "\"first\nmiddle\nlast\"")])

        let prefixEdit = SyntaxHighlightEditContext(
            replacementRange: NSRange(location: 0, length: 0),
            replacementString: "🌟 ",
            replacedText: ""
        )
        var updatedText = "🌟 \(original)"
        ranges = try XCTUnwrap(highlighter.updatedMultilineTokenRanges(
            ranges,
            cachedTextLength: originalNSString.length,
            editContext: prefixEdit,
            in: updatedText as NSString
        ))

        let middleRange = (updatedText as NSString).range(of: "middle")
        let lineEdit = SyntaxHighlightEditContext(
            replacementRange: middleRange,
            replacementString: "middle expanded",
            replacedText: "middle"
        )
        updatedText = (updatedText as NSString).replacingCharacters(in: middleRange, with: lineEdit.replacementString)
        ranges = try XCTUnwrap(highlighter.updatedMultilineTokenRanges(
            ranges,
            cachedTextLength: ("🌟 \(original)" as NSString).length,
            editContext: lineEdit,
            in: updatedText as NSString
        ))

        let expected = (updatedText as NSString).range(of: "\"first\nmiddle expanded\nlast\"")
        XCTAssertEqual(ranges, [expected])
        XCTAssertEqual(
            highlighter.expandedHighlightRange(
                for: (updatedText as NSString).range(of: "middle expanded"),
                cachedMultilineTokenRanges: ranges,
                in: updatedText as NSString
            ),
            expected
        )

        let structuralRange = (updatedText as NSString).range(of: "middle expanded")
        let structuralEdit = SyntaxHighlightEditContext(
            replacementRange: structuralRange,
            replacementString: "'",
            replacedText: "middle expanded"
        )
        let structurallyUpdatedText = (updatedText as NSString).replacingCharacters(in: structuralRange, with: "'")
        XCTAssertNil(highlighter.updatedMultilineTokenRanges(
            ranges,
            cachedTextLength: (updatedText as NSString).length,
            editContext: structuralEdit,
            in: structurallyUpdatedText as NSString
        ))
    }

    func testBashAndJSONTokenRangesUseUTF16OffsetsWithUnicode() {
        let bashText = "echo \"👨‍👩‍👧‍👦\"\nexport NAME=🌈\necho $HOME"
        let bashStorage = makeHighlightedStorage(bashText, language: .bash)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let bashNSString = bashText as NSString
        assertColor(theme.string, at: bashNSString.range(of: "👨‍👩‍👧‍👦").location, in: bashStorage)
        assertColor(theme.variable, at: bashNSString.range(of: "$HOME").location, in: bashStorage)

        let jsonText = "{\"👨‍👩‍👧‍👦\": \"🌈\", \"count\": 42}"
        let jsonStorage = makeHighlightedStorage(jsonText, language: .json)
        let jsonNSString = jsonText as NSString
        assertColor(theme.propertyKey, at: jsonNSString.range(of: "\"👨‍👩‍👧‍👦\"").location, in: jsonStorage)
        assertColor(theme.string, at: jsonNSString.range(of: "\"🌈\"").location + 1, in: jsonStorage)
        assertColor(theme.variable, at: jsonNSString.range(of: "42").location, in: jsonStorage)
    }

    func testSSHConfigHighlighterStylesKeywordsValuesAndComments() {
        let text = """
        Include ~/.colima/ssh_config
        Host github-personal
          HostName github.com
        # comment
        """

        let storage = makeHighlightedStorage(text, language: .sshconfig)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.keyword, at: nsText.range(of: "Include").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "~/.colima/ssh_config").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "Host ").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "github-personal").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "# comment").location, in: storage)
    }

    func testJSONHighlighterStylesKeysValuesLiteralsAndPunctuation() {
        let text = """
        {
          "name": "vmini",
          "enabled": true,
          "count": 42,
          "ratio": -3.5e+2,
          "data": null,
          "items": [1, false]
        }
        """

        let storage = makeHighlightedStorage(text, language: .json)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.operator, at: nsText.range(of: "{").location, in: storage)
        assertColor(theme.propertyKey, at: nsText.range(of: "\"name\"").location + 1, in: storage)
        assertColor(theme.string, at: nsText.range(of: "\"vmini\"").location + 1, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "true").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "42").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "-3.5e+2").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "null").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: "[").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "false").location, in: storage)
    }

    func testYAMLHighlighterStylesKeysValuesCommentsAndOperators() {
        let text = """
        # comment
        name: "vmini"
        enabled: true
        count: 42
        ratio: -3.5e+2
        items:
          - "one"
        flow: { retries: 3 }
        """

        let storage = makeHighlightedStorage(text, language: .yaml)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.comment, at: nsText.range(of: "# comment").location, in: storage)
        assertColor(theme.propertyKey, at: nsText.range(of: "name").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: ":").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "\"vmini\"").location + 1, in: storage)
        assertColor(theme.string, at: nsText.range(of: "vmini").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "true").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "42").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "-3.5e+2").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: "- \"one\"").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: "{").location, in: storage)
        assertColor(theme.propertyKey, at: nsText.range(of: "retries").location, in: storage)
    }

    func testYAMLHighlighterStylesBareScalarValuesAsStrings() {
        let text = """
        apiVersion: v1
        server: https://example.com
        name: ske-8f53bik
        """

        let storage = makeHighlightedStorage(text, language: .yaml)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.propertyKey, at: nsText.range(of: "apiVersion").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "v1").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "https://example.com").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "ske-8f53bik").location, in: storage)
    }

    func testEditorViewControllerAppliesAndClearsMarkdownHighlighting() async throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title"

        let storage = try XCTUnwrap(viewController.textStorage)
        let nsText = viewController.text as NSString
        let syntaxTheme = ThemeManager.shared.syntaxTheme
        let h1Color = syntaxTheme.headingMarker
        try await waitForCondition {
            let markerColor = storage.attribute(.foregroundColor, at: nsText.range(of: "#").location, effectiveRange: nil) as? NSColor
            let titleColor = storage.attribute(.foregroundColor, at: nsText.range(of: "Title").location, effectiveRange: nil) as? NSColor
            let markerFont = storage.attribute(.font, at: nsText.range(of: "#").location, effectiveRange: nil) as? NSFont
            let titleFont = storage.attribute(.font, at: nsText.range(of: "Title").location, effectiveRange: nil) as? NSFont
            return markerColor?.isEqual(syntaxTheme.headingMarker) == true
                && titleColor?.isEqual(h1Color) == true
                && markerFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
                && titleFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
        }
        assertColor(syntaxTheme.headingMarker, at: nsText.range(of: "#").location, in: storage)
        assertColor(h1Color, at: nsText.range(of: "Title").location, in: storage)
        assertBoldFont(at: nsText.range(of: "#").location, in: storage)
        assertBoldFont(at: nsText.range(of: "Title").location, in: storage)

        viewController.syntaxLanguage = .plaintext
        try await waitForCondition {
            let markerColor = storage.attribute(.foregroundColor, at: nsText.range(of: "#").location, effectiveRange: nil) as? NSColor
            let markerFont = storage.attribute(.font, at: nsText.range(of: "#").location, effectiveRange: nil) as? NSFont
            return markerColor?.isEqual(syntaxTheme.plainText) == true
                && markerFont?.fontDescriptor.symbolicTraits.contains(.bold) != true
        }
        assertColor(syntaxTheme.plainText, at: nsText.range(of: "#").location, in: storage)
        assertNonBoldFont(at: nsText.range(of: "#").location, in: storage)
    }

    func testEditorViewControllerUsesShellCommentPrefixForBash() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .bash
        viewController.text = "echo hi"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        viewController.toggleLineComment()

        XCTAssertEqual(viewController.text, "#echo hi")
    }

    func testEditorViewControllerUsesShellCommentPrefixForSSHConfig() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .sshconfig
        viewController.text = "Host github"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        viewController.toggleLineComment()

        XCTAssertEqual(viewController.text, "#Host github")
    }

    func testEditorViewControllerUsesHashCommentPrefixForYAML() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .yaml
        viewController.text = "name: value"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        viewController.toggleLineComment()

        XCTAssertEqual(viewController.text, "#name: value")
    }

    func testDocumentSyntaxLanguageUsesDotfileNameAndShebangContent() throws {
        let dotfileDocument = Document()
        dotfileDocument.fileURL = URL(fileURLWithPath: "/tmp/.zshenv")
        try dotfileDocument.read(from: Data("export PATH=/tmp".utf8), ofType: UTType.plainText.identifier)
        XCTAssertEqual(dotfileDocument.syntaxLanguage, .bash)

        let shebangDocument = Document()
        shebangDocument.fileURL = URL(fileURLWithPath: "/tmp/config")
        try shebangDocument.read(from: Data("#!/bin/sh\necho hi\n".utf8), ofType: UTType.plainText.identifier)
        XCTAssertEqual(shebangDocument.syntaxLanguage, .sshconfig)
    }

    func testSavedFileSyntaxOverridePersistsAcrossDocuments() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let store = SyntaxOverrideStore(userDefaults: userDefaults)
        let fileURL = URL(fileURLWithPath: "/tmp/example.md")

        let document = Document(syntaxOverrideStore: store)
        document.fileURL = fileURL
        await Task.yield()
        document.setSyntaxLanguageOverride(.json)

        let reopenedDocument = Document(syntaxOverrideStore: store)
        reopenedDocument.fileURL = fileURL
        await Task.yield()

        XCTAssertTrue(reopenedDocument.hasSyntaxLanguageOverride)
        XCTAssertEqual(reopenedDocument.syntaxLanguage, .json)
    }

    func testUnsavedFileSyntaxOverrideDoesNotPersistAcrossDocuments() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let store = SyntaxOverrideStore(userDefaults: userDefaults)

        let document = Document(syntaxOverrideStore: store)
        document.setSyntaxLanguageOverride(.bash)

        let reopenedDocument = Document(syntaxOverrideStore: store)

        XCTAssertFalse(reopenedDocument.hasSyntaxLanguageOverride)
        XCTAssertEqual(reopenedDocument.syntaxLanguage, .plaintext)
    }

    func testUnsavedSyntaxOverridePersistsAfterSavingFile() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let store = SyntaxOverrideStore(userDefaults: userDefaults)
        let fileURL = URL(fileURLWithPath: "/tmp/example.json")

        let document = Document(syntaxOverrideStore: store)
        document.setSyntaxLanguageOverride(.markdown)
        document.fileURL = fileURL
        await Task.yield()

        let reopenedDocument = Document(syntaxOverrideStore: store)
        reopenedDocument.fileURL = fileURL
        await Task.yield()

        XCTAssertTrue(reopenedDocument.hasSyntaxLanguageOverride)
        XCTAssertEqual(reopenedDocument.syntaxLanguage, .markdown)
    }

    private func makeHighlightedStorage(_ text: String, language: SyntaxLanguage) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let baseFont = EditorFontResolver.font(for: .fallback, size: 13)
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: baseFont, range: fullRange)
        storage.addAttribute(.foregroundColor, value: theme.plainText, range: fullRange)
        HighlighterRegistry.shared.highlighter(for: language).highlight(
            textStorage: storage,
            in: fullRange,
            baseFont: baseFont,
            theme: theme,
            registry: HighlighterRegistry.shared
        )
        return storage
    }

    private func unhighlightedStorage(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: EditorFontResolver.font(for: .fallback, size: 13), range: fullRange)
        storage.addAttribute(.foregroundColor, value: ThemeCatalog.palette(for: .default).syntaxTheme.plainText, range: fullRange)
        return storage
    }

    private func applyEdit(
        _ replacement: String,
        at location: Int,
        in storage: NSTextStorage,
        controller: EditorSyntaxHighlightController,
        language: SyntaxLanguage = .markdown
    ) {
        applyEdit(
            replacement,
            replacing: NSRange(location: location, length: 0),
            in: storage,
            controller: controller,
            language: language
        )
    }

    private func applyEdit(
        _ replacement: String,
        replacing range: NSRange,
        in storage: NSTextStorage,
        controller: EditorSyntaxHighlightController,
        language: SyntaxLanguage = .markdown
    ) {
        let oldText = storage.string as NSString
        let editContext = SyntaxHighlightEditContext(
            replacementRange: range,
            replacementString: replacement,
            replacedText: oldText.substring(with: range)
        )
        storage.replaceCharacters(in: range, with: replacement)
        controller.handleProcessedEditing(
            editedMask: [.editedCharacters],
            editedRange: NSRange(location: range.location, length: (replacement as NSString).length),
            language: language,
            editContext: editContext
        )
    }

    private func highlightingMatchesFresh(_ storage: NSTextStorage, language: SyntaxLanguage) -> Bool {
        let fresh = makeHighlightedStorage(storage.string, language: language)
        guard storage.length == fresh.length else { return false }

        for index in 0..<storage.length {
            for key in [NSAttributedString.Key.foregroundColor, .backgroundColor, .font] {
                let actual = storage.attribute(key, at: index, effectiveRange: nil)
                let expected = fresh.attribute(key, at: index, effectiveRange: nil)
                if actual == nil || expected == nil {
                    if actual != nil || expected != nil { return false }
                } else if let actual = actual as? NSObject,
                          let expected = expected as? NSObject,
                          !actual.isEqual(expected) {
                    return false
                } else if !(actual is NSObject), !(expected is NSObject) {
                    return false
                }
            }
        }
        return true
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    private func assertColor(_ expected: NSColor, at location: Int, in storage: NSTextStorage, file: StaticString = #filePath, line: UInt = #line) {
        let actual = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(actual, file: file, line: line)
        XCTAssertTrue(actual?.isEqual(expected) == true, file: file, line: line)
    }

    private func assertBackgroundColor(_ expected: NSColor, at location: Int, in storage: NSTextStorage, file: StaticString = #filePath, line: UInt = #line) {
        let actual = storage.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(actual, file: file, line: line)
        XCTAssertTrue(actual?.isEqual(expected) == true, file: file, line: line)
    }

    private func assertBoldFont(at location: Int, in storage: NSTextStorage, file: StaticString = #filePath, line: UInt = #line) {
        let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font, file: file, line: line)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, file: file, line: line)
    }

    private func assertNonBoldFont(at location: Int, in storage: NSTextStorage, file: StaticString = #filePath, line: UInt = #line) {
        let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font, file: file, line: line)
        XCTAssertFalse(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, file: file, line: line)
    }

    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollNanoseconds: UInt64 = 25_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }

        XCTFail("Timed out waiting for condition")
    }
}
