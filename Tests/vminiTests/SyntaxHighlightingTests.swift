import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import vmini

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
            .bash
        )
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(
                fileURL: URL(fileURLWithPath: "/tmp/config"),
                typeIdentifier: UTType.text.identifier,
                content: "plain text"
            ),
            .plaintext
        )
    }

    func testLanguageResolverRecognizesShellFenceInfoStrings() {
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("sh"), .bash)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("bash"), .bash)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("zsh"), .bash)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("shell"), .bash)
    }

    func testLanguageResolverDefaultsOtherTextFilesToPlaintext() {
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/notes.txt"), typeIdentifier: UTType.plainText.identifier),
            .plaintext
        )
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/config"), typeIdentifier: UTType.text.identifier),
            .plaintext
        )
    }

    func testMarkdownHighlighterStylesCoreMarkdownTokens() throws {
        let text = """
        # Title
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

        assertColor(theme.headingMarker, at: nsText.range(of: "#").location, in: storage)
        assertColor(theme.headingText, at: nsText.range(of: "Title").location, in: storage)
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

    func testBashHighlighterStylesCoreShellTokens() {
        let text = """
        # comment
        if [ \"$HOME\" = \"foo\" ]; then
          export PATH=$(pwd)
          echo '$USER'
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
    }

    func testEditorViewControllerAppliesAndClearsMarkdownHighlighting() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title"

        let storage = try XCTUnwrap(viewController.textStorage)
        let nsText = viewController.text as NSString
        assertColor(ThemeCatalog.palette(for: .default).syntaxTheme.headingMarker, at: nsText.range(of: "#").location, in: storage)

        viewController.syntaxLanguage = .plaintext
        assertColor(ThemeCatalog.palette(for: .default).syntaxTheme.plainText, at: nsText.range(of: "#").location, in: storage)
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

    func testDocumentSyntaxLanguageUsesDotfileNameAndShebangContent() throws {
        let dotfileDocument = Document()
        dotfileDocument.fileURL = URL(fileURLWithPath: "/tmp/.zshenv")
        try dotfileDocument.read(from: Data("export PATH=/tmp".utf8), ofType: UTType.plainText.identifier)
        XCTAssertEqual(dotfileDocument.syntaxLanguage, .bash)

        let shebangDocument = Document()
        shebangDocument.fileURL = URL(fileURLWithPath: "/tmp/config")
        try shebangDocument.read(from: Data("#!/bin/sh\necho hi\n".utf8), ofType: UTType.plainText.identifier)
        XCTAssertEqual(shebangDocument.syntaxLanguage, .bash)
    }

    private func makeHighlightedStorage(_ text: String, language: SyntaxLanguage) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.foregroundColor, value: theme.plainText, range: fullRange)
        HighlighterRegistry.shared.highlighter(for: language).highlight(
            textStorage: storage,
            in: fullRange,
            theme: theme,
            registry: HighlighterRegistry.shared
        )
        return storage
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
}
