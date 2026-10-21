import AppKit
import XCTest
@testable import vmini

@MainActor
private final class LinkHoverTestWindow: NSWindow {
    var testMouseLocation = NSPoint.zero
    override var mouseLocationOutsideOfEventStream: NSPoint { testMouseLocation }
}

@MainActor
final class EditorMarkdownLinkTests: XCTestCase {
    func testLinkDetectionUsesLabelRangesAndIgnoresNonLinks() {
        let text = "😀 [café 👋](notes/你好.md) and [google](https://www.google.com)"
        let source = text as NSString
        for label in ["café 👋", "google"] {
            let range = source.range(of: label)
            let expected = label == "google" ? "https://www.google.com" : "notes/你好.md"
            XCTAssertEqual(MarkdownLink.destination(in: text, at: range.location), expected)
            XCTAssertEqual(MarkdownLink.destination(in: text, at: range.location + range.length - 1), expected)
            XCTAssertNil(MarkdownLink.destination(in: text, at: range.location - 1))
            XCTAssertNil(MarkdownLink.destination(in: text, at: range.location + range.length))
        }
        XCTAssertNil(MarkdownLink.destination(in: text, at: source.range(of: "notes/").location))
        XCTAssertNil(MarkdownLink.destination(in: text, at: source.length))
        XCTAssertNil(MarkdownLink.destination(in: text, at: -1))
        for text in [
            "😀 `[label](file.md)`", "```md\n[label](file.md)\n```",
            "~~~\n[label](file.md)\n~~~", "![label](image.png)",
            #"\[label](file.md)"#, "[label](file.md", "[label] no destination",
        ] {
            XCTAssertNil(MarkdownLink.destination(in: text, at: (text as NSString).range(of: "label").location), text)
        }
        XCTAssertEqual(MarkdownLink.destination(in: "[broken] [label](ok.md)", at: 11), "ok.md")
        XCTAssertEqual(MarkdownLink.destination(in: "[label](notes/a(b).md)", at: 2), "notes/a(b).md")
    }

    func testDestinationsResolveRelativeToMarkdownDocument() {
        let base = URL(fileURLWithPath: "/tmp/project/docs/readme.md")
        for (destination, path) in [
            ("aaa.md", "/tmp/project/docs/aaa.md"),
            ("../local/aaa.md", "/tmp/project/local/aaa.md"),
            ("/local/aaa.md", "/local/aaa.md"),
            ("<notes/my file.md>", "/tmp/project/docs/notes/my file.md"),
            ("caf%C3%A9.md#heading", "/tmp/project/docs/café.md"),
            ("file:///tmp/aaa.md", "/tmp/aaa.md"),
        ] {
            let url = MarkdownLink.resolve(destination, relativeTo: base)
            XCTAssertEqual(url?.path, path, destination)
            XCTAssertEqual(url?.isFileURL, true)
        }
        XCTAssertEqual(MarkdownLink.resolve("https://www.google.com", relativeTo: nil)?.absoluteString, "https://www.google.com")
        XCTAssertEqual(MarkdownLink.resolve("http://example.com/a?q=1#b", relativeTo: base)?.absoluteString, "http://example.com/a?q=1#b")
        XCTAssertNil(MarkdownLink.resolve("aaa.md", relativeTo: nil))
        XCTAssertNotNil(MarkdownLink.resolve("/tmp/aaa.md", relativeTo: nil))
        for invalid in ["", "#heading", "javascript:alert(1)", "data:text/html,test"] {
            XCTAssertNil(MarkdownLink.resolve(invalid, relativeTo: base))
        }
    }

    func testCommandClickRoutesLinksAndPreservesSelection() throws {
        let document = Document()
        document.fileURL = URL(fileURLWithPath: "/tmp/project/readme.md")
        document.setSyntaxLanguageOverride(.markdown)
        let editor = document.editorViewController(onFileSystemURLsDropped: { _ in })
        editor.loadViewIfNeeded()
        editor.text = "😀 [local](aaa.md) [web](https://www.google.com)"
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        textView.setSelectedRange(NSRange(location: 0, length: 2))
        var opened: [URL] = []
        editor.onOpenURL = { opened.append($0) }

        for (label, expected) in [("local", "file:///tmp/project/aaa.md"), ("web", "https://www.google.com")] {
            let index = (editor.text as NSString).range(of: label).location
            textView.mouseDown(with: try mouseEvent(in: textView, at: point(in: textView, at: index), type: .leftMouseDown))
            XCTAssertEqual(opened.last?.absoluteString, expected)
            XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 2))
        }
        let localIndex = (editor.text as NSString).range(of: "local").location
        document.fileURL = URL(fileURLWithPath: "/tmp/moved/readme.md")
        XCTAssertEqual(textView.onCommandClick?(localIndex), true)
        XCTAssertEqual(opened.last?.path, "/tmp/moved/aaa.md")
        editor.syntaxLanguage = .plaintext
        XCTAssertEqual(textView.onCommandClick?(localIndex), false)
        editor.syntaxLanguage = .markdown
        editor.text = "[local](different.md)"
        XCTAssertEqual(textView.onCommandClick?(2), true)
        XCTAssertEqual(opened.last?.path, "/tmp/moved/different.md")
        XCTAssertEqual(opened.count, 4)
        editor.text = "[https://example.com](https://destination.example.org)"
        XCTAssertEqual(textView.onCommandClick?(2), true)
        XCTAssertEqual(opened.last?.absoluteString, "https://destination.example.org")
    }

    func testCommandHoverTracksTargetsAndModifierChanges() throws {
        let (editor, textView, window) = try makeHoverEditor()
        defer { window.close() }
        let initialCursor = NSCursor.current
        defer { initialCursor.set() }
        var opened = false
        editor.onOpenURL = { _ in opened = true }

        for (token, modifiers, expectedCursor) in [
            ("web", NSEvent.ModifierFlags.command, NSCursor.pointingHand),
            ("web", [], NSCursor.iBeam),
            ("local", .command, NSCursor.pointingHand),
            ("[", .command, NSCursor.iBeam),
            ("https", .command, NSCursor.pointingHand),
            ("code", .command, NSCursor.iBeam),
        ] {
            let index = (editor.text as NSString).range(of: token).location
            let event = try mouseEvent(in: textView, at: point(in: textView, at: index), modifiers: modifiers)
            textView.mouseMoved(with: event)
            XCTAssertEqual(NSCursor.current, expectedCursor, token)
            textView.cursorUpdate(with: event)
            XCTAssertEqual(NSCursor.current, expectedCursor, token)
        }
        let targetCheck = try XCTUnwrap(textView.isCommandClickTarget)
        let label = (editor.text as NSString).range(of: "web")
        let first = try point(in: textView, at: label.location)
        window.testMouseLocation = textView.convert(first, to: nil)
        for modifiers: NSEvent.ModifierFlags in [[], .command, []] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 55
            ))
            textView.flagsChanged(with: event)
            XCTAssertEqual(NSCursor.current, modifiers.contains(.command) ? NSCursor.pointingHand : NSCursor.iBeam)
        }
        editor.syntaxLanguage = .plaintext
        XCTAssertFalse(targetCheck(label.location))
        editor.syntaxLanguage = .markdown
        editor.documentURLProvider = nil
        XCTAssertFalse(targetCheck((editor.text as NSString).range(of: "local").location))
        XCTAssertFalse(opened)
    }

    func testMovingAcrossLinkKeepsHandCursor() throws {
        let (editor, textView, window) = try makeHoverEditor()
        defer { window.close() }
        let initialCursor = NSCursor.current
        defer { initialCursor.set() }
        let targetCheck = try XCTUnwrap(textView.isCommandClickTarget)
        textView.isCommandClickTarget = { index in
            XCTAssertEqual(NSCursor.current, NSCursor.pointingHand, "Mouse movement must not briefly restore the text cursor")
            return targetCheck(index)
        }
        NSCursor.pointingHand.set()
        let label = (editor.text as NSString).range(of: "web")
        let first = try point(in: textView, at: label.location)
        let last = try point(in: textView, at: label.location + label.length - 1)
        for x in stride(from: first.x, through: last.x, by: 0.25) {
            textView.mouseMoved(with: try mouseEvent(in: textView, at: NSPoint(x: x, y: first.y)))
            XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
        }
    }

    func testWebURLDetectionHandlesPunctuationUnicodeAndOnlyWebSchemes() {
        let source = "😀 (https://example.com/a?q=1#part), http://example.org.\nwww.example.net"
        let matches = WebLink.matches(in: source, range: NSRange(location: 0, length: source.utf16.count))
        XCTAssertEqual(matches.compactMap(\.url).map(\.absoluteString), [
            "https://example.com/a?q=1#part", "http://example.org", "http://www.example.net"
        ])
        for match in matches {
            XCTAssertEqual(WebLink.url(in: source, at: match.range.location), match.url)
            XCTAssertEqual(WebLink.url(in: source, at: NSMaxRange(match.range) - 1), match.url)
            XCTAssertNil(WebLink.url(in: source, at: match.range.location - 1))
            XCTAssertNil(WebLink.url(in: source, at: NSMaxRange(match.range)))
        }
        for source in ["", "plain text", "mailto:user@example.com", "ftp://example.com", "file:///tmp/readme.md"] {
            XCTAssertTrue(WebLink.matches(in: source, range: NSRange(location: 0, length: source.utf16.count)).isEmpty, source)
        }
        XCTAssertNil(WebLink.url(in: source, at: -1))
        XCTAssertNil(WebLink.url(in: source, at: source.utf16.count))
    }

    func testWebURLsSupportCommandClickAndHandCursorInEveryLanguage() throws {
        let (editor, textView, window) = try makeHoverEditor()
        defer { window.close() }
        let initialCursor = NSCursor.current
        defer { initialCursor.set() }
        editor.text = "😀 https://example.com/a?q=1#part plain"
        let range = (editor.text as NSString).range(of: "https://example.com/a?q=1#part")
        var opened: [URL] = []
        editor.onOpenURL = { opened.append($0) }
        for (languageIndex, language) in SyntaxLanguage.allCases.enumerated() {
            editor.syntaxLanguage = language
            textView.setSelectedRange(NSRange(location: 0, length: 2))
            let linkPoint = try point(in: textView, at: range.location)
            for modifiers: NSEvent.ModifierFlags in [[], .command, []] {
                let event = try mouseEvent(in: textView, at: linkPoint, modifiers: modifiers)
                let expectedCursor = modifiers.contains(.command) ? NSCursor.pointingHand : NSCursor.iBeam
                textView.mouseMoved(with: event)
                XCTAssertEqual(NSCursor.current, expectedCursor, language.rawValue)
                textView.cursorUpdate(with: event)
                XCTAssertEqual(NSCursor.current, expectedCursor, language.rawValue)
            }
            XCTAssertEqual(opened.count, languageIndex)
            textView.mouseDown(with: try mouseEvent(in: textView, at: linkPoint, type: .leftMouseDown))
            XCTAssertEqual(opened.last?.absoluteString, "https://example.com/a?q=1#part")
            XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 2))
            let plainPoint = try point(in: textView, at: (editor.text as NSString).range(of: "plain").location)
            textView.mouseMoved(with: try mouseEvent(in: textView, at: plainPoint, modifiers: []))
            XCTAssertEqual(NSCursor.current, NSCursor.iBeam)
        }
        editor.text = "plain text"
        XCTAssertEqual(textView.onCommandClick?(range.location), false)
    }

    func testWebURLStylingSurvivesSyntaxChangesAndClearsAfterEditing() async throws {
        let editor = EditorViewController()
        editor.loadViewIfNeeded()
        editor.text = "{\"url\": \"https://example.com\"}\n"
        let storage = try XCTUnwrap(editor.textStorage)
        let index = (editor.text as NSString).range(of: "https").location
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        for language in SyntaxLanguage.allCases {
            editor.syntaxLanguage = language
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertEqual(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor, .systemBlue, language.rawValue)
            XCTAssertEqual(storage.attribute(.underlineStyle, at: index, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
            XCTAssertNil(storage.attribute(.underlineStyle, at: 0, effectiveRange: nil))
            textView.insertText("plain", replacementRange: (editor.text as NSString).range(of: "https://example.com"))
            XCTAssertEqual(textView.isCommandClickTarget?(index), false)
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertNil(storage.attribute(.underlineStyle, at: index, effectiveRange: nil))
            XCTAssertNotEqual(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor, .systemBlue)
            textView.insertText("https://example.com", replacementRange: NSRange(location: index, length: 5))
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertEqual(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor, .systemBlue)
            XCTAssertEqual(storage.attribute(.underlineStyle, at: index, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        }
    }

    private func makeHoverEditor() throws -> (EditorViewController, EditorTextView, LinkHoverTestWindow) {
        let editor = EditorViewController()
        editor.syntaxLanguage = .markdown
        editor.loadViewIfNeeded()
        editor.text = "😀 [web](https://example.com) [local](aaa.md) `[code](https://example.com)`"
        editor.documentURLProvider = { URL(fileURLWithPath: "/tmp/readme.md") }
        let textView = try XCTUnwrap(findTextView(in: editor.view))
        textView.frame = NSRect(x: 0, y: 0, width: 1200, height: 200)
        let window = LinkHoverTestWindow(
            contentRect: textView.frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = textView
        return (editor, textView, window)
    }

    private func mouseEvent(
        in textView: EditorTextView, at point: NSPoint,
        type: NSEvent.EventType = .mouseMoved, modifiers: NSEvent.ModifierFlags = .command
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: textView.convert(point, to: nil), modifierFlags: modifiers,
            timestamp: 0, windowNumber: textView.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 0
        ))
    }

    private func point(in textView: EditorTextView, at index: Int) throws -> NSPoint {
        let layout = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        return NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y)
    }

    private func findTextView(in view: NSView) -> EditorTextView? {
        (view as? EditorTextView) ?? view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }
}
