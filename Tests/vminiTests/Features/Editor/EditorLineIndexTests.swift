import XCTest
@testable import vmini

final class EditorLineIndexTests: XCTestCase {
    func testIncrementalEditsKeepUTF16LineStartsAndLookupsCorrect() {
        let text = NSMutableString(string: "one\n😀 two\nthree\n")
        var index = EditorLineIndex()
        index.reset(text: text)
        assertIndex(index, matches: text)

        for (original, replacement) in [
            ("two", "TWO\nnew"),
            ("one\n", ""),
            ("\nthree", "\n"),
            ("new", "\nnew\n"),
            ("😀", "é"),
            ("TWO", ""),
        ] {
            let range = text.range(of: original)
            XCTAssertNotEqual(range.location, NSNotFound)
            guard range.location != NSNotFound else { return }
            text.replaceCharacters(in: range, with: replacement)
            index.update(
                text: text,
                editedRange: NSRange(location: range.location, length: replacement.utf16.count),
                changeInLength: replacement.utf16.count - range.length
            )
            assertIndex(index, matches: text)
        }

        let previousLength = text.length
        text.setString("")
        index.update(text: text, editedRange: NSRange(location: 0, length: 0), changeInLength: -previousLength)
        assertIndex(index, matches: text)
        text.setString("😀\n\n")
        index.update(text: text, editedRange: NSRange(location: 0, length: text.length), changeInLength: text.length)
        assertIndex(index, matches: text)
    }

    func testResetHandlesEmptyTextAndNewlinesAcrossScanBuffers() {
        var index = EditorLineIndex()
        for text in ["", "\n", String(repeating: "x", count: 65_535) + "\n😀\nend"] {
            index.reset(text: text as NSString)
            assertIndex(index, matches: text as NSString)
        }
    }

    private func assertIndex(_ index: EditorLineIndex, matches text: NSString, file: StaticString = #filePath, line: UInt = #line) {
        let lines = (text as String).components(separatedBy: "\n")
        var expectedStarts = [0]
        for content in lines.dropLast() {
            expectedStarts.append(expectedStarts.last! + content.utf16.count + 1)
        }
        XCTAssertEqual(index.lineStarts, expectedStarts, file: file, line: line)
        for (offset, start) in expectedStarts.enumerated() {
            let end = offset + 1 < expectedStarts.count ? expectedStarts[offset + 1] - 1 : text.length
            for location in [start, end] {
                XCTAssertEqual(index.index(containing: location), offset, file: file, line: line)
                XCTAssertEqual(index.lineNumber(forCharacterAt: location), offset + 1, file: file, line: line)
            }
        }
    }
}
