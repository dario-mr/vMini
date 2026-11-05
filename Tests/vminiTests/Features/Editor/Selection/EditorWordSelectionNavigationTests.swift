import AppKit
import XCTest
@testable import vmini

@MainActor
final class EditorWordSelectionNavigationTests: XCTestCase {
    func testRepeatedOptionShiftLeftStopsAtWordsPrefixesAndBlankLines() throws {
        let cases: [(String, [String])] = [
            ("", ["", ""]),
            ("alpha beta", ["beta", "alpha beta", "alpha beta"]),
            ("one\n    word", ["word", "    word", "one\n    word"]),
            ("one\n\tword", ["word", "\tword", "one\n\tword"]),
            ("one\n--- word", ["word", "--- word", "one\n--- word"]),
            ("one\n\n\nword", ["word", "\nword", "\n\nword", "one\n\n\nword"]),
            ("one\n \t\nword", ["word", " \t\nword", "one\n \t\nword"]),
            ("one\r\n\r\n    word", ["word", "    word", "\r\n    word", "one\r\n\r\n    word"]),
            ("one\r\r    word", ["word", "    word", "\r    word", "one\r\r    word"]),
            ("one\u{2028}--- word", ["word", "--- word", "one\u{2028}--- word"]),
            ("😀\n    café", ["café", "    café", "😀\n    café"]),
        ]
        for (source, selections) in cases {
            let (window, textView) = makeTextView(source)
            defer { window.orderOut(nil) }
            for selected in selections {
                textView.keyDown(with: try keyEvent(in: window))
                XCTAssertEqual(textView.selectedRange(), NSRange(
                    location: source.utf16.count - selected.utf16.count, length: selected.utf16.count
                ), "\(source.debugDescription), selecting \(selected.debugDescription)")
                XCTAssertEqual(textView.string, source)
            }
        }
    }

    func testRepeatedOptionShiftLeftCrossesWrappedPrefixes() throws {
        for prefix in [String(repeating: "-", count: 60) + " ", String(repeating: " ", count: 60)] {
            let source = "one\n" + prefix + "word"
            let (window, textView) = makeTextView(source, width: 150)
            defer { window.orderOut(nil) }
            let layout = try XCTUnwrap(textView.layoutManager)
            var fragment = NSRange()
            _ = layout.lineFragmentRect(
                forGlyphAt: layout.glyphIndexForCharacter(at: source.utf16.count - 4), effectiveRange: &fragment
            )
            XCTAssertGreaterThan(fragment.location, "one\n".utf16.count, "The word must be on a wrapped line")

            for selected in ["word", prefix + "word", source, source] {
                textView.keyDown(with: try keyEvent(in: window))
                XCTAssertEqual(textView.selectedRange(), NSRange(
                    location: source.utf16.count - selected.utf16.count, length: selected.utf16.count
                ), prefix.debugDescription)
            }
            XCTAssertEqual(textView.string, source)
        }
    }

    func testOtherKeysResetTheOptionShiftLeftSequence() throws {
        let (window, textView) = makeTextView("one\n--- word")
        defer { window.orderOut(nil) }
        textView.keyDown(with: try keyEvent(in: window))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 4))

        textView.keyDown(with: try keyEvent(in: window, modifiers: [.shift, .function]))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 7, length: 5))
        textView.keyDown(with: try keyEvent(in: window))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 12))
    }

    func testExistingSelectionsKeepNativeWordMovement() throws {
        let (window, textView) = makeTextView("one\n--- word")
        defer { window.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 8, length: 4))

        textView.keyDown(with: try keyEvent(in: window))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 12))
    }

    private func makeTextView(_ source: String, width: CGFloat = 600) -> (NSWindow, EditorTextView) {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: width, height: 300)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        let textView = EditorTextView(frame: frame)
        textView.textContainer?.replaceLayoutManager(NSLayoutManager())
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isRichText = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.string = source
        window.contentView = textView
        window.makeFirstResponder(textView)
        if let container = textView.textContainer { textView.layoutManager?.ensureLayout(for: container) }
        textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        return (window, textView)
    }

    private func keyEvent(in window: NSWindow,
                          modifiers: NSEvent.ModifierFlags = [.option, .shift, .function]) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{f702}",
            charactersIgnoringModifiers: "\u{f702}", isARepeat: false, keyCode: 123
        ))
    }
}
