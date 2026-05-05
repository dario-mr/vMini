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
        let theme = SyntaxTheme.default
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
        assertColor(theme.plainText, at: nsText.range(of: "echo hi").location, in: storage)
        assertBackgroundColor(theme.codeBlockBackground, at: nsText.range(of: "echo hi").location, in: storage)
    }

    func testEditorViewControllerAppliesAndClearsMarkdownHighlighting() throws {
        let viewController = EditorViewController()
        viewController.loadViewIfNeeded()
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title"

        let storage = try XCTUnwrap(viewController.textStorage)
        let nsText = viewController.text as NSString
        assertColor(SyntaxTheme.default.headingMarker, at: nsText.range(of: "#").location, in: storage)

        viewController.syntaxLanguage = .plaintext
        assertColor(SyntaxTheme.default.plainText, at: nsText.range(of: "#").location, in: storage)
    }

    private func makeHighlightedStorage(_ text: String, language: SyntaxLanguage) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let theme = SyntaxTheme.default
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
