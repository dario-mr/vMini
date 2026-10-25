import AppKit
import UniformTypeIdentifiers
import XCTest
import SwiftTreeSitter
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

    func testLanguageResolverAndRegistryRecognizeKotlin() {
        for fileName in ["Main.kt", "build.kts"] {
            XCTAssertEqual(
                SyntaxLanguageResolver.resolve(
                    fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
                    typeIdentifier: UTType.plainText.identifier
                ),
                .kotlin
            )
        }

        let registry = HighlighterRegistry.shared
        XCTAssertTrue(registry.highlighter(for: .kotlin) is KotlinSyntaxHighlighter)
        for infoString in ["kotlin", "kt", "kts"] {
            XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString(infoString), .kotlin)
            XCTAssertTrue(registry.highlighter(forFenceInfoString: infoString) as? KotlinSyntaxHighlighter != nil)
        }
    }

    func testLanguageResolverAndRegistryRecognizeJava25() {
        for fileName in ["Main.java", "module-info.java"] {
            XCTAssertEqual(
                SyntaxLanguageResolver.resolve(
                    fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
                    typeIdentifier: UTType.plainText.identifier
                ),
                .java
            )
        }

        let registry = HighlighterRegistry.shared
        XCTAssertTrue(registry.highlighter(for: .java) is JavaSyntaxHighlighter)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("java"), .java)
        XCTAssertTrue(registry.highlighter(forFenceInfoString: "java") is JavaSyntaxHighlighter)
    }

    func testLanguageResolverAndRegistryRecognizeSQL() {
        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(
                fileURL: URL(fileURLWithPath: "/tmp/query.SQL"),
                typeIdentifier: UTType.plainText.identifier
            ),
            .sql
        )

        let registry = HighlighterRegistry.shared
        XCTAssertTrue(registry.highlighter(for: .sql) is SQLSyntaxHighlighter)
        for infoString in ["sql", "postgresql"] {
            XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString(infoString), .sql)
            XCTAssertTrue(registry.highlighter(forFenceInfoString: infoString) is SQLSyntaxHighlighter)
        }
    }

    func testLanguageResolverRecognizesDotenvFileNames() {
        for fileName in [".env", ".env.development", ".env.development.local", ".ENV.Production"] {
            XCTAssertEqual(
                SyntaxLanguageResolver.resolve(
                    fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
                    typeIdentifier: UTType.plainText.identifier
                ),
                .dotenv
            )
        }

        XCTAssertEqual(
            SyntaxLanguageResolver.resolve(fileURL: URL(fileURLWithPath: "/tmp/.envrc"), typeIdentifier: UTType.plainText.identifier),
            .plaintext
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
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("env"), .dotenv)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("dotenv"), .dotenv)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("json"), .json)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("yaml"), .yaml)
        XCTAssertEqual(SyntaxLanguageResolver.resolveFenceInfoString("yml"), .yaml)
    }

    func testTreeSitterGrammarSelectionAndHighlightingForEverySyntax() {
        let cases: [(language: SyntaxLanguage, grammar: String, text: String, token: String, role: SyntaxColorRole, editToken: String, replacement: String)] = [
            (.bash, "bash", "echo $HOME", "$HOME", .variable, "$HOME", "$USER"),
            (.dotenv, "bash", "NAME=hello", "hello", .string, "hello", "world"),
            (.sshconfig, "ssh_config", "Host example.com", "Host", .keyword, "example.com", "example.org"),
            (.markdown, "markdown", "# Heading", "#", .headingMarker, "Heading", "Changed"),
            (.json, "json", "{\"name\": 1}", "\"name\"", .propertyKey, "name", "kind"),
            (.yaml, "yaml", "enabled: false", "false", .keyword, "false", "true"),
            (.kotlin, "kotlin", "fun main() {}", "fun", .keyword, "main", "test"),
            (.java, "java", "class Example {}", "class", .keyword, "Example", "Example2"),
            (.sql, "sql", "SELECT 1 FROM users", "SELECT", .keyword, "users", "accounts"),
        ]
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme

        for sample in cases {
            XCTAssertEqual(TreeSitterSyntaxGrammar.name(for: sample.language), sample.grammar)
            guard let definition = TreeSitterSyntaxGrammar.definition(for: sample.language) else {
                XCTFail("Missing Tree-sitter definition for \(sample.language)")
                continue
            }
            XCTAssertTrue(definition.highlightsQuery === TreeSitterSyntaxGrammar.definition(for: sample.language)?.highlightsQuery)
            if sample.language == .markdown {
                XCTAssertNotNil(definition.inlineHighlightsQuery)
                XCTAssertNotNil(definition.inlineRangesQuery)
                XCTAssertTrue(definition.inlineHighlightsQuery === TreeSitterSyntaxGrammar.definition(for: .markdown)?.inlineHighlightsQuery)
                XCTAssertTrue(definition.inlineRangesQuery === TreeSitterSyntaxGrammar.definition(for: .markdown)?.inlineRangesQuery)
            }
            let storage = makeHighlightedStorage(sample.text, language: sample.language)
            let tokenRange = (sample.text as NSString).range(of: sample.token)
            XCTAssertNotEqual(tokenRange.location, NSNotFound, "Missing test token for \(sample.language)")
            let actualColor = storage.attribute(.foregroundColor, at: tokenRange.location, effectiveRange: nil) as? NSColor
            let expectedColor = sample.language == .markdown && sample.role == .headingMarker
                ? theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha)
                : theme.color(for: sample.role)
            XCTAssertTrue(
                actualColor?.isEqual(expectedColor) == true,
                "Expected \(sample.role) on \(sample.language) token \(sample.token)"
            )

            let source = sample.text as NSString
            let editRange = source.range(of: sample.editToken)
            let edit = SyntaxHighlightEditContext(
                replacementRange: editRange,
                replacementString: sample.replacement,
                replacedText: source.substring(with: editRange)
            )
            let editedText = source.replacingCharacters(in: editRange, with: sample.replacement)
            let parser = TreeSitterSyntaxParser(language: sample.language)
            _ = parser.highlight(text: sample.text, in: nil)
            let incremental = parser.highlight(text: editedText, in: nil, edits: [edit])
            let fresh = TreeSitterSyntaxParser(language: sample.language).highlight(text: editedText, in: nil)
            XCTAssertEqual(
                incremental.tokens.map { "\($0.range.location):\($0.range.length):\(String(describing: $0.role))" },
                fresh.tokens.map { "\($0.range.location):\($0.range.length):\(String(describing: $0.role))" },
                "Incremental parse diverged for \(sample.language)"
            )
        }

        XCTAssertNil(TreeSitterSyntaxGrammar.name(for: .plaintext))
        assertColor(theme.plainText, at: 0, in: makeHighlightedStorage("plain text", language: .plaintext))
    }

    func testMarkdownInlineAndCodeFenceUseTreeSitterHighlighting() {
        let text = "# Inline `code`\n\n```json\n{\"name\": 1}\n```"
        let storage = makeHighlightedStorage(text, language: .markdown)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.inlineCode, at: nsText.range(of: "`code`").location, in: storage)
        assertColor(theme.propertyKey, at: nsText.range(of: "\"name\"").location, in: storage)
    }

    func testMarkdownCodeFencesDispatchEveryTreeSitterSyntax() {
        let samples: [(info: String, code: String, token: String, role: SyntaxColorRole)] = [
            ("sh", "echo $HOME", "$HOME", .variable),
            ("dotenv", "NAME=hello", "hello", .string),
            ("sshconfig", "Host example.com", "Host", .keyword),
            ("json", "{\"name\": 1}", "\"name\"", .propertyKey),
            ("yaml", "enabled: true", "true", .keyword),
            ("kotlin", "fun main() {}", "fun", .keyword),
            ("java", "class Example {}", "class", .keyword),
            ("sql", "SELECT 1", "SELECT", .keyword),
            ("markdown", "# Nested heading", "#", .headingMarker),
        ]
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme

        for sample in samples {
            let text = "```\(sample.info)\n\(sample.code)\n```"
            let storage = makeHighlightedStorage(text, language: .markdown)
            let tokenLocation = (text as NSString).range(of: sample.token).location
            assertColor(theme.color(for: sample.role), at: tokenLocation, in: storage)
        }
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
        let headingColors = MarkdownAttributeStyler.Constants.headingColorStrengths.map {
            theme.headingText.blended(withFraction: $0, of: theme.headingMarker) ?? theme.headingText
        }
        let markerColor = theme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha)

        assertColor(markerColor, at: nsText.range(of: "#").location, in: storage)
        assertColor(headingColors[0], at: nsText.range(of: "Title").location, in: storage)
        assertBoldFont(at: nsText.range(of: "#").location, in: storage)
        assertBoldFont(at: nsText.range(of: "Title").location, in: storage)
        assertColor(headingColors[1], at: nsText.range(of: "Subtitle").location, in: storage)
        assertColor(headingColors[2], at: nsText.range(of: "Section").location, in: storage)
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

    func testMarkdownHeadingHierarchyKeepsDimmedMarkersAndSourceText() throws {
        let markerAlpha = MarkdownAttributeStyler.Constants.headingMarkerAlpha
        let text = "# One\n## Two\n### Three\n#### Four\n##### Five\n###### Six\nBody\n```\n# Code\n```\n#hashtag\n####### Invalid"
        let nsText = text as NSString
        for themeID in ThemeID.allCases {
            let theme = ThemeCatalog.palette(for: themeID).syntaxTheme
            for size: CGFloat in [13, 20] {
                let baseFont = EditorFontResolver.font(for: .fallback, size: size)
                let storage = NSTextStorage(string: text, attributes: [.font: baseFont])
                MarkdownSyntaxHighlighter().highlight(
                    textStorage: storage, in: nil, baseFont: baseFont, theme: theme, registry: .shared
                )

                for (index, title) in ["One", "Two", "Three", "Four", "Five", "Six"].enumerated() {
                    let marker = String(repeating: "#", count: index + 1)
                    let markerRange = nsText.range(of: marker + " " + title)
                    let titleLocation = nsText.range(of: title).location
                    let titleFont = try XCTUnwrap(storage.attribute(.font, at: titleLocation, effectiveRange: nil) as? NSFont)
                    let markerFont = try XCTUnwrap(storage.attribute(.font, at: markerRange.location, effectiveRange: nil) as? NSFont)
                    XCTAssertEqual(titleFont.pointSize, size * MarkdownAttributeStyler.Constants.headingScales[index], accuracy: 0.001)
                    XCTAssertEqual(titleFont.familyName, baseFont.familyName)
                    XCTAssertEqual(markerFont, titleFont)
                    assertBoldFont(at: titleLocation, in: storage)
                    for offset in 0..<marker.count {
                        assertColor(theme.headingMarker.withAlphaComponent(markerAlpha), at: markerRange.location + offset, in: storage)
                    }
                    let titleColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: titleLocation, effectiveRange: nil) as? NSColor)
                    XCTAssertGreaterThan(titleColor.alphaComponent, markerAlpha)
                }
                for ordinaryText in ["Body", "# Code", "#hashtag", "####### Invalid"] {
                    let font = storage.attribute(.font, at: nsText.range(of: ordinaryText).location, effectiveRange: nil) as? NSFont
                    XCTAssertEqual(font, baseFont)
                }
                XCTAssertEqual(storage.string, text)
            }
        }
    }

    func testMarkdownHeadingSizeUpdatesAndResetsAfterEditingMarkers() async throws {
        let storage = unhighlightedStorage("# Heading\nBody")
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

        applyEdit("##", replacing: NSRange(location: 0, length: 1), in: storage, controller: controller)
        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }

        applyEdit("", replacing: NSRange(location: 0, length: 3), in: storage, controller: controller)
        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }
        XCTAssertEqual(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, baseFont)
        assertColor(theme.plainText, at: 0, in: storage)
    }

    func testKotlinHighlighterStylesCoreTokens() {
        let text = [
            "class Greeter {",
            "    fun greet(name: String): String = \"Hello, $name\"",
            "    val raw = \"\"\"multi",
            "line raw\"\"\"",
            "    /* outer",
            "       /* nested */ still comment */",
            "    // line comment",
            "    val answer = 42",
            "    val transform: (String) -> String = { value -> value }",
            "}",
        ].joined(separator: "\n")
        let storage = makeHighlightedStorage(text, language: .kotlin)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.keyword, at: nsText.range(of: "fun").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "String").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "Hello").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "multi\nline raw").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "outer").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "still comment").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "line comment").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "42").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: "->").location, in: storage)
    }

    func testKotlinTreeSitterIncrementalEditsMatchFreshHighlighting() {
        assertIncrementalHighlightingMatchesFresh(
            language: .kotlin,
            source: "/* outer\nval hidden = 1\n*/\nval shown = 2",
            edits: [("/*", "//"), ("//", "/*")]
        )
    }

    func testJavaHighlighterStylesJava25AndCoreTokens() {
        let text = [
            "import module java.base;",
            "sealed interface Shape permits Circle {}",
            "non-sealed class Circle {}",
            "record Point(int x) {}",
            "@RestController",
            "@org.example.RequestMapping(\"/api\")",
            "@interface CustomAnnotation {}",
            "class Demo {",
            "  String greeting = \"hi\";",
            "  String text = \"\"\"",
            "    text block class",
            "    \"\"\";",
            "  char marker = 'J';",
            "  long value = 0x2A_FFL;",
            "  void run() { // line comment",
            "    /* block comment */ if (value > 0) return;",
            "    case String item when item.length() > 0 -> item;",
            "    RoomEntity room = roomRepository.createRoom(roomId);",
            "  }",
            "}",
        ].joined(separator: "\n")
        let storage = makeHighlightedStorage(text, language: .java)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        for keyword in ["module", "sealed", "permits", "non-sealed", "record", "when"] {
            assertColor(theme.keyword, at: nsText.range(of: keyword).location, in: storage)
        }
        assertColor(theme.builtin, at: nsText.range(of: "RestController").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "org.example.RequestMapping").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "interface", options: .backwards).location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "String").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "Demo {").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "createRoom").location, in: storage)
        for identifier in ["room", "roomRepository", "roomId"] {
            assertColor(theme.plainText, at: nsText.range(of: identifier).location, in: storage)
        }
        assertColor(theme.string, at: nsText.range(of: "hi").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "text block class").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "J").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "0x2A_FFL").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "line comment").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "block comment").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: ">", options: .backwards).location, in: storage)
    }

    func testSQLHighlighterStylesCoreTokens() {
        let text = [
            "SELECT COUNT(*) FROM \"user table\" JOIN users ON users.id = users.id",
            "WHERE id = :id AND status = 'active' -- line comment",
            "  AND total >= 42;",
            "/* outer",
            "   /* nested */ still comment",
            "*/",
            "SELECT $$dollar string$$;",
            "SELECT CAST(score AS INTEGER) FROM users;",
            "SELECT ?;",
        ].joined(separator: "\n")
        let storage = makeHighlightedStorage(text, language: .sql)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.keyword, at: nsText.range(of: "SELECT").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "ON").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "COUNT").location, in: storage)
        assertColor(theme.propertyKey, at: nsText.range(of: "user table").location, in: storage)
        assertColor(theme.plainText, at: nsText.range(of: "id =").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: ":id").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "active").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "line comment").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: ">=").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "42").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "still comment").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "dollar string").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "INTEGER").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "?").location, in: storage)
    }

    func testMarkdownSQLFenceStylesSQLTokens() {
        let text = """
        ```sql
        SELECT origin.item_code
        FROM entities AS origin
        WHERE origin.item_code IS NOT NULL
          AND origin.item_code = 'alpha'
          AND origin.item_code IN ('alpha', 'beta');
        ```
        """
        let storage = makeHighlightedStorage(text, language: .markdown)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.keyword, at: nsText.range(of: "SELECT").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "WHERE").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "AND").location, in: storage)
        let isRange = nsText.range(of: "IS NOT")
        XCTAssertNotEqual(isRange.location, NSNotFound)
        assertColor(theme.keyword, throughout: NSRange(location: isRange.location, length: 2), in: storage)
        assertColor(theme.keyword, throughout: NSRange(location: isRange.location + 3, length: 3), in: storage)
        assertColor(theme.string, at: nsText.range(of: "alpha").location, in: storage)
        assertColor(theme.builtin, at: nsText.range(of: "NULL").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: "= 'alpha'").location, in: storage)
        for identifier in [
            "origin", "item_code", "entities",
        ] {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.length > 0 {
                let identifierRange = nsText.range(of: identifier, range: searchRange)
                guard identifierRange.location != NSNotFound else { break }
                assertColor(theme.plainText, throughout: identifierRange, in: storage)
                searchRange = NSRange(
                    location: NSMaxRange(identifierRange),
                    length: nsText.length - NSMaxRange(identifierRange)
                )
            }
        }
    }

    func testSQLTreeSitterIncrementalEditsMatchFreshHighlighting() {
        assertIncrementalHighlightingMatchesFresh(
            language: .sql,
            source: "SELECT 1; -- trailing comment\nSELECT 2;",
            edits: [("--", "/*"), ("/*", "--")]
        )
    }

    func testJavaHighlighterLeavesRangeExpansionToTheIncrementalParser() {
        let highlighter = JavaSyntaxHighlighter()

        for (delimiter, replacement) in [("/*", "//"), ("\"\"\"", "\"")] {
            let oldText = "before\n\(delimiter) content\nend" as NSString
            let replacedRange = oldText.range(of: delimiter)
            let editContext = SyntaxHighlightEditContext(
                replacementRange: replacedRange,
                replacementString: replacement,
                replacedText: delimiter
            )
            let updatedText = oldText.replacingCharacters(in: replacedRange, with: replacement) as NSString
            let editedRange = NSRange(location: replacedRange.location, length: (replacement as NSString).length)
            let expandedRange = highlighter.expandedHighlightRange(
                for: editedRange,
                editContext: editContext,
                in: updatedText
            )

            XCTAssertEqual(expandedRange, updatedText.lineRange(for: editedRange))
        }

        let text = "one\ntwo\nthree" as NSString
        let replacedRange = text.range(of: "two")
        let editContext = SyntaxHighlightEditContext(
            replacementRange: replacedRange,
            replacementString: "TWO",
            replacedText: "two"
        )
        let updatedText = text.replacingCharacters(in: replacedRange, with: "TWO") as NSString
        let editedRange = updatedText.range(of: "TWO")
        let expandedRange = highlighter.expandedHighlightRange(
            for: editedRange,
            editContext: editContext,
            in: updatedText
        )

        XCTAssertEqual(expandedRange, updatedText.lineRange(for: editedRange))
        XCTAssertLessThan(expandedRange.length, updatedText.length)
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

    func testMarkdownHighlighterColorsNestedListMarkers() {
        for indentation in ["    ", "        ", "\t", "\t\t", "\t  "] {
            for marker in ["-", "*", "+", "1.", "10)"] {
                for suffix in ["", " ", " item", "\titem"] {
                    let text = "🙂\n- parent\n" + indentation + marker + suffix
                    let storage = makeHighlightedStorage(text, language: .markdown)
                    let theme = ThemeCatalog.palette(for: .default).syntaxTheme
                    let markerLocation = "🙂\n- parent\n".utf16.count + indentation.utf16.count
                    for index in markerLocation..<(markerLocation + marker.utf16.count) {
                        assertColor(theme.listMarker, at: index, in: storage)
                    }
                    assertColor(theme.plainText, at: markerLocation - 1, in: storage)
                }
            }
        }
        let text = "```\n    - item\n    1. item\n```"
        let storage = makeHighlightedStorage(text, language: .markdown)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        assertColor(theme.plainText, at: (text as NSString).range(of: "- item").location, in: storage)
        assertColor(theme.plainText, at: (text as NSString).range(of: "1. item").location, in: storage)
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

    func testCancelledMarkdownWorkRecolorsAndRejectsStaleResults() async throws {
        let storage = unhighlightedStorage("# Initial\nfirst\nsecond\nthird\nordinary\nfifth\nsixth\n")
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let font = EditorFontResolver.font(for: .fallback, size: 13)
        var holdWork = false
        var workStarted = expectation(description: "first edit started")
        var completions: [() -> Void] = []
        var workRanges: [NSRange] = []
        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: .shared,
            textStorageProvider: { storage }, syntaxThemeProvider: { theme }, baseFontProvider: { font },
            markdownWorkProvider: { highlighter, snapshot, range, cachedFenceCache, _ in
                let cache = cachedFenceCache ?? highlighter.makeFenceCache(in: snapshot as NSString)
                let result = MarkdownSyntaxHighlighter.HighlightWork(
                    fenceCache: cache,
                    lineStyles: highlighter.lineStylePlan(in: snapshot, targetRange: range, fences: cache.blocks),
                    fenceHighlights: MarkdownFenceHighlighter.highlights(in: snapshot, targetRange: range, fences: cache.blocks) ?? []
                )
                return Task { @MainActor in
                    if holdWork {
                        await withCheckedContinuation { continuation in
                            completions.append { continuation.resume() }
                            workRanges.append(range)
                            workStarted.fulfill()
                        }
                    }
                    return result
                }
            }
        )
        controller.refresh(language: .markdown)
        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }

        holdWork = true
        applyEdit("# Heading", replacing: (storage.string as NSString).range(of: "ordinary"), in: storage, controller: controller)
        await fulfillment(of: [workStarted], timeout: 2)
        workStarted = expectation(description: "replacement work started")
        applyEdit("😀 prefix\n", at: 0, in: storage, controller: controller)
        await fulfillment(of: [workStarted], timeout: 2)

        // Complete the newer work first, then deliver the cancelled result with stale offsets.
        XCTAssertEqual(completions.count, 2)
        guard completions.count == 2 else { return }
        completions[1]()
        try await waitForCondition { self.highlightingMatchesFresh(storage, language: .markdown) }
        completions[0]()
        await Task.yield()
        XCTAssertTrue(highlightingMatchesFresh(storage, language: .markdown))
        let heading = (storage.string as NSString).range(of: "Heading")
        XCTAssertEqual(NSIntersectionRange(workRanges[1], heading), heading)
        XCTAssertEqual(workRanges[1], NSRange(location: 0, length: storage.length), "Repaint the discarded parser result")
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

    func testTypingInMarkdownHeadingCopiesAdjacentAttributesAfterEditCallback() async throws {
        let text = "## Title"
        let storage = makeHighlightedStorage(text, language: .markdown)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let baseFont = EditorFontResolver.font(for: .fallback, size: 13)
        let controller = EditorSyntaxHighlightController(
            highlighterRegistry: .shared,
            textStorageProvider: { storage },
            syntaxThemeProvider: { theme },
            baseFontProvider: { baseFont },
            markdownWorkProvider: { _, _, _, _, _ in Task { nil } }
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

        let strength = MarkdownAttributeStyler.Constants.headingColorStrengths[1]
        let expectedColor = theme.headingText.blended(withFraction: strength, of: theme.headingMarker) ?? theme.headingText

        assertColor(theme.plainText, at: insertionLocation, in: storage)
        try await waitForCondition {
            (storage.attribute(.foregroundColor, at: insertionLocation, effectiveRange: nil) as? NSColor)
                .map { $0.isEqual(expectedColor) } == true
        }
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

    func testDotenvHighlighterStylesAssignmentsCommentsAndVariables() {
        let text = """
        # comment
        CLUSTER=winterfell
        LIA_ENABLED=false
        export API_URL="${API_HOST}/v1" # inline comment
        LITERAL='$VAR'
        """

        let storage = makeHighlightedStorage(text, language: .dotenv)
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        let nsText = text as NSString

        assertColor(theme.comment, at: nsText.range(of: "# comment").location, in: storage)
        assertColor(theme.propertyKey, at: nsText.range(of: "CLUSTER").location, in: storage)
        assertColor(theme.operator, at: nsText.range(of: "=").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "winterfell").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "false").location, in: storage)
        assertColor(theme.keyword, at: nsText.range(of: "export").location, in: storage)
        assertColor(theme.variable, at: nsText.range(of: "${API_HOST}").location, in: storage)
        assertColor(theme.comment, at: nsText.range(of: "# inline comment").location, in: storage)
        assertColor(theme.string, at: nsText.range(of: "$VAR").location, in: storage)
    }

    func testBashTreeSitterHighlightsMultilineStringsAfterUnicodeEdits() {
        let original = "echo done\nprintf \"first\nmiddle\nlast\"\necho end"
        let parser = TreeSitterSyntaxParser(language: .bash)
        _ = parser.highlight(text: original, in: nil)

        let prefixEdit = SyntaxHighlightEditContext(
            replacementRange: NSRange(location: 0, length: 0),
            replacementString: "🌟 ",
            replacedText: ""
        )
        var updatedText = "🌟 \(original)"
        _ = parser.highlight(text: updatedText, in: nil, edits: [prefixEdit])

        let middleRange = (updatedText as NSString).range(of: "middle")
        let lineEdit = SyntaxHighlightEditContext(
            replacementRange: middleRange,
            replacementString: "middle expanded",
            replacedText: "middle"
        )
        updatedText = (updatedText as NSString).replacingCharacters(in: middleRange, with: lineEdit.replacementString)
        let work = parser.highlight(text: updatedText, in: nil, edits: [lineEdit])
        let expected = (updatedText as NSString).range(of: "\"first\nmiddle expanded\nlast\"")
        let theme = ThemeCatalog.palette(for: .default).syntaxTheme
        XCTAssertTrue(work.tokens.contains {
            $0.range == expected && theme.color(for: $0.role).isEqual(theme.string)
        })
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
        _ = viewController.view
        viewController.syntaxLanguage = .markdown
        viewController.text = "# Title"

        let storage = try XCTUnwrap(viewController.textStorage)
        let nsText = viewController.text as NSString
        let syntaxTheme = ThemeManager.shared.syntaxTheme
        let strength = MarkdownAttributeStyler.Constants.headingColorStrengths[0]
        let h1Color = syntaxTheme.headingText.blended(withFraction: strength, of: syntaxTheme.headingMarker) ?? syntaxTheme.headingText
        let expectedMarkerColor = syntaxTheme.headingMarker.withAlphaComponent(MarkdownAttributeStyler.Constants.headingMarkerAlpha)
        try await waitForCondition {
            let markerColor = storage.attribute(.foregroundColor, at: nsText.range(of: "#").location, effectiveRange: nil) as? NSColor
            let titleColor = storage.attribute(.foregroundColor, at: nsText.range(of: "Title").location, effectiveRange: nil) as? NSColor
            let markerFont = storage.attribute(.font, at: nsText.range(of: "#").location, effectiveRange: nil) as? NSFont
            let titleFont = storage.attribute(.font, at: nsText.range(of: "Title").location, effectiveRange: nil) as? NSFont
            return markerColor?.isEqual(expectedMarkerColor) == true
                && titleColor?.isEqual(h1Color) == true
                && markerFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
                && titleFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
        }
        assertColor(expectedMarkerColor, at: nsText.range(of: "#").location, in: storage)
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

    func testEditorViewControllerUsesSlashSlashCommentPrefixForJava() throws {
        let viewController = EditorViewController()
        _ = viewController.view
        viewController.syntaxLanguage = .java
        viewController.text = "class Demo {}"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        viewController.toggleLineComment()

        XCTAssertEqual(viewController.text, "//class Demo {}")
    }

    func testEditorViewControllerUsesShellCommentPrefixForBash() throws {
        let viewController = EditorViewController()
        _ = viewController.view
        viewController.syntaxLanguage = .bash
        viewController.text = "echo hi"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        viewController.toggleLineComment()

        XCTAssertEqual(viewController.text, "#echo hi")
    }

    func testEditorViewControllerUsesShellCommentPrefixForSSHConfig() throws {
        let viewController = EditorViewController()
        _ = viewController.view
        viewController.syntaxLanguage = .sshconfig
        viewController.text = "Host github"

        let textView = try XCTUnwrap(findTextView(in: viewController.view))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        viewController.toggleLineComment()

        XCTAssertEqual(viewController.text, "#Host github")
    }

    func testEditorViewControllerUsesHashCommentPrefixForYAML() throws {
        let viewController = EditorViewController()
        _ = viewController.view
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

    private func assertIncrementalHighlightingMatchesFresh(
        language: SyntaxLanguage,
        source: String,
        edits: [(replaced: String, replacement: String)]
    ) {
        var text = source
        let parser = TreeSitterSyntaxParser(language: language)
        _ = parser.highlight(text: text, in: nil)

        for edit in edits {
            let oldText = text as NSString
            let range = oldText.range(of: edit.replaced)
            XCTAssertNotEqual(range.location, NSNotFound)
            let context = SyntaxHighlightEditContext(
                replacementRange: range,
                replacementString: edit.replacement,
                replacedText: oldText.substring(with: range)
            )
            text = oldText.replacingCharacters(in: range, with: edit.replacement)
            let incremental = parser.highlight(text: text, in: nil, edits: [context])
            let fresh = TreeSitterSyntaxParser(language: language).highlight(text: text, in: nil)
            XCTAssertEqual(
                incremental.tokens.map { "\($0.range.location):\($0.range.length):\(String(describing: $0.role))" },
                fresh.tokens.map { "\($0.range.location):\($0.range.length):\(String(describing: $0.role))" },
                "Incremental parse diverged for \(language) after replacing \(edit.replaced)"
            )
        }
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
        XCTAssertTrue(actual?.isEqual(expected) == true, "Expected \(expected), got \(String(describing: actual)) at UTF-16 offset \(location)", file: file, line: line)
    }

    private func assertColor(_ expected: NSColor, throughout range: NSRange, in storage: NSTextStorage, file: StaticString = #filePath, line: UInt = #line) {
        for location in range.location..<NSMaxRange(range) {
            assertColor(expected, at: location, in: storage, file: file, line: line)
        }
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
