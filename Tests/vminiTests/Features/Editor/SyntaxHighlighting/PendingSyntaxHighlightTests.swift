import XCTest
@testable import vmini

final class PendingSyntaxHighlightTests: XCTestCase {
    func testRangesTrackInsertionsDeletionsAndOverlappingReplacements() {
        for (edit, newLength, expectedRange) in [
            (SyntaxHighlightEditContext(replacementRange: NSRange(location: 1, length: 0), replacementString: "😀", replacedText: ""), 12, NSRange(location: 6, length: 3)),
            (SyntaxHighlightEditContext(replacementRange: NSRange(location: 8, length: 0), replacementString: "x", replacedText: ""), 11, NSRange(location: 4, length: 3)),
            (SyntaxHighlightEditContext(replacementRange: NSRange(location: 0, length: 2), replacementString: "", replacedText: "ab"), 8, NSRange(location: 2, length: 3)),
            (SyntaxHighlightEditContext(replacementRange: NSRange(location: 3, length: 3), replacementString: "x", replacedText: "abc"), 8, NSRange(location: 3, length: 2)),
            (SyntaxHighlightEditContext(replacementRange: NSRange(location: 3, length: 5), replacementString: "😀", replacedText: "abcde"), 7, NSRange(location: 3, length: 2)),
        ] {
            var pending = PendingSyntaxHighlight.range(NSRange(location: 4, length: 3), textLength: 10)
            pending.adjust(for: edit, currentTextLength: newLength)
            XCTAssertEqual(pending, .range(expectedRange, textLength: newLength))
        }
    }

    func testMissingOrInconsistentEditContextRequiresFullHighlight() {
        for edit in [
            nil,
            SyntaxHighlightEditContext(replacementRange: NSRange(location: 1, length: 0), replacementString: "xx", replacedText: ""),
            SyntaxHighlightEditContext(replacementRange: NSRange(location: 1, length: 2), replacementString: "x", replacedText: "a"),
            SyntaxHighlightEditContext(replacementRange: NSRange(location: 11, length: 0), replacementString: "x", replacedText: ""),
        ] {
            var pending = PendingSyntaxHighlight.range(NSRange(location: 4, length: 3), textLength: 10)
            pending.adjust(for: edit, currentTextLength: 11)
            XCTAssertEqual(pending, .full)
        }
    }

    func testMergingClampsRangesAndPreservesFullHighlightRequests() {
        var pending = PendingSyntaxHighlight.none
        XCTAssertTrue(pending.isEmpty)
        pending.adjust(for: nil, currentTextLength: 10)
        XCTAssertEqual(pending, .none)
        pending.merge(NSRange(location: 2, length: 2), textLength: 10)
        XCTAssertFalse(pending.isEmpty)
        pending.merge(NSRange(location: 7, length: 20), textLength: 10)
        XCTAssertEqual(pending, .range(NSRange(location: 2, length: 8), textLength: 10))
        pending.merge(NSRange(location: 0, length: 10), textLength: 10)
        XCTAssertEqual(pending, .full)
        pending.adjust(for: nil, currentTextLength: 12)
        pending.merge(NSRange(location: 3, length: 1), textLength: 12)
        XCTAssertEqual(pending, .full)
    }

    func testSuccessiveEditsUseTheUpdatedTextLength() {
        var pending = PendingSyntaxHighlight.range(NSRange(location: 4, length: 3), textLength: 10)
        let insertion = SyntaxHighlightEditContext(replacementRange: NSRange(location: 0, length: 0), replacementString: "😀", replacedText: "")
        pending.adjust(for: insertion, currentTextLength: 12)
        pending.merge(NSRange(location: 0, length: 2), textLength: 12)
        let deletion = SyntaxHighlightEditContext(replacementRange: NSRange(location: 0, length: 2), replacementString: "", replacedText: "😀")
        pending.adjust(for: deletion, currentTextLength: 10)
        pending.merge(NSRange(location: 0, length: 1), textLength: 10)
        XCTAssertEqual(pending, .range(NSRange(location: 0, length: 7), textLength: 10))
    }
}
