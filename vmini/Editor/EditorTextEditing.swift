import AppKit

struct EditorCursorPosition {
    let line: Int
    let column: Int

    var displayText: String {
        "Ln \(line), Col \(column)"
    }
}

struct EditorTextEdit {
    let replacementRange: NSRange
    let replacementText: String
    let selectedRange: NSRange
}

enum EditorLineMoveDirection {
    case up
    case down
}

enum EditorTextEditing {
    static func currentCursorPosition(in text: NSString, selectedRange: NSRange) -> EditorCursorPosition {
        let clampedSelectedRange = clampedRange(selectedRange, toLength: text.length)
        let selectedLocation = clampedSelectedRange.location
        let line = lineNumber(for: selectedLocation, in: text)
        let lineRange = text.lineRange(for: NSRange(location: selectedLocation, length: 0))
        let lineStart = min(lineRange.location, selectedLocation)
        let prefixRange = NSRange(location: lineStart, length: selectedLocation - lineStart)
        let column = text.substring(with: prefixRange).count + 1
        return EditorCursorPosition(line: line, column: column)
    }

    static func characterLocation(forLineNumber lineNumber: Int, in text: NSString) -> Int {
        guard lineNumber > 1 else { return 0 }

        var currentLine = 1
        var scanLocation = 0
        while scanLocation < text.length, currentLine < lineNumber {
            let lineRange = text.lineRange(for: NSRange(location: scanLocation, length: 0))
            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > scanLocation else { break }
            scanLocation = nextLocation
            currentLine += 1
        }

        return min(scanLocation, text.length)
    }

    static func toggleLineComment(
        in text: NSString,
        selectedRange: NSRange,
        syntaxLanguage: SyntaxLanguage
    ) -> EditorTextEdit? {
        let clampedSelectedRange = clampedRange(selectedRange, toLength: text.length)
        let affectedRange = affectedLineRange(in: text, selectedRange: clampedSelectedRange)
        let edits = commentEdits(in: text, affectedRange: affectedRange, syntaxLanguage: syntaxLanguage)
        guard !edits.isEmpty else { return nil }

        let replacement = NSMutableString(string: text.substring(with: affectedRange))
        for edit in edits.reversed() {
            replacement.replaceCharacters(
                in: NSRange(location: edit.location - affectedRange.location, length: edit.removedLength),
                with: edit.insertedText
            )
        }

        let newSelectionStart = transformedPosition(clampedSelectedRange.location, byApplying: edits)
        let newSelectionEnd = transformedPosition(NSMaxRange(clampedSelectedRange), byApplying: edits)

        return EditorTextEdit(
            replacementRange: affectedRange,
            replacementText: replacement as String,
            selectedRange: NSRange(
                location: min(newSelectionStart, newSelectionEnd),
                length: abs(newSelectionEnd - newSelectionStart)
            )
        )
    }

    static func duplicateSelectedLines(in text: NSString, selectedRange: NSRange) -> EditorTextEdit {
        let clampedSelectedRange = clampedRange(selectedRange, toLength: text.length)
        let affectedRange = affectedLineRange(in: text, selectedRange: clampedSelectedRange)
        let duplicatedText = duplicatedLineBlockText(for: affectedRange, in: text)
        let selectionOffset = (duplicatedText as NSString).length

        return EditorTextEdit(
            replacementRange: NSRange(location: NSMaxRange(affectedRange), length: 0),
            replacementText: duplicatedText,
            selectedRange: NSRange(
                location: clampedSelectedRange.location + selectionOffset,
                length: clampedSelectedRange.length
            )
        )
    }

    static func moveSelectedLines(
        in text: NSString,
        selectedRange: NSRange,
        direction: EditorLineMoveDirection
    ) -> EditorTextEdit? {
        let clampedSelectedRange = clampedRange(selectedRange, toLength: text.length)
        let affectedRange = affectedLineRange(in: text, selectedRange: clampedSelectedRange)

        let swap: LineSwapOperation
        switch direction {
        case .up:
            guard let previousRange = previousAdjacentLineRange(before: affectedRange, in: text) else { return nil }
            swap = swappedAdjacentLineBlocks(upperRange: previousRange, lowerRange: affectedRange, in: text)
        case .down:
            guard let nextRange = nextAdjacentLineRange(after: affectedRange, in: text) else { return nil }
            swap = swappedAdjacentLineBlocks(upperRange: affectedRange, lowerRange: nextRange, in: text)
        }

        let selectionLocationDelta = direction == .up
            ? swap.lowerSelectionLocationDelta
            : swap.upperSelectionLocationDelta

        return EditorTextEdit(
            replacementRange: swap.replacedRange,
            replacementText: swap.replacementText,
            selectedRange: NSRange(
                location: clampedSelectedRange.location + selectionLocationDelta,
                length: clampedSelectedRange.length
            )
        )
    }

    private struct CommentEdit {
        let location: Int
        let removedLength: Int
        let insertedText: String

        var insertedLength: Int {
            (insertedText as NSString).length
        }
    }

    private struct LineSwapOperation {
        let replacedRange: NSRange
        let replacementText: String
        let upperSelectionLocationDelta: Int
        let lowerSelectionLocationDelta: Int
    }

    private static func lineCommentPrefix(for syntaxLanguage: SyntaxLanguage) -> String {
        switch syntaxLanguage {
        case .bash, .sshconfig:
            "#"
        case .plaintext, .markdown, .json:
            "//"
        }
    }

    private static func lineNumber(for characterLocation: Int, in text: NSString) -> Int {
        let clampedLocation = min(max(characterLocation, 0), text.length)
        var lineNumber = 1
        var scanLocation = 0

        while scanLocation < clampedLocation {
            let lineRange = text.lineRange(for: NSRange(location: scanLocation, length: 0))
            guard NSMaxRange(lineRange) <= clampedLocation else { break }
            lineNumber += 1
            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > scanLocation else { break }
            scanLocation = nextLocation
        }

        return lineNumber
    }

    private static func affectedLineRange(in text: NSString, selectedRange: NSRange) -> NSRange {
        let textLength = text.length
        let selectedLocation = min(selectedRange.location, textLength)

        guard selectedRange.length > 0 else {
            return text.lineRange(for: NSRange(location: selectedLocation, length: 0))
        }

        let selectionEnd = min(NSMaxRange(selectedRange), textLength)
        let lastSelectedCharacter = max(selectedLocation, selectionEnd - 1)
        let firstLineRange = text.lineRange(for: NSRange(location: selectedLocation, length: 0))
        let lastLineRange = text.lineRange(for: NSRange(location: lastSelectedCharacter, length: 0))
        return NSRange(location: firstLineRange.location, length: NSMaxRange(lastLineRange) - firstLineRange.location)
    }

    private static func duplicatedLineBlockText(for affectedRange: NSRange, in text: NSString) -> String {
        let lineText = text.substring(with: affectedRange)
        if NSMaxRange(affectedRange) < text.length || lineText.hasSuffix("\n") {
            return lineText
        }
        return "\n" + lineText
    }

    private static func previousAdjacentLineRange(before affectedRange: NSRange, in text: NSString) -> NSRange? {
        guard affectedRange.location > 0 else { return nil }
        return text.lineRange(for: NSRange(location: affectedRange.location - 1, length: 0))
    }

    private static func nextAdjacentLineRange(after affectedRange: NSRange, in text: NSString) -> NSRange? {
        let nextLocation = NSMaxRange(affectedRange)
        guard nextLocation < text.length else { return nil }
        return text.lineRange(for: NSRange(location: nextLocation, length: 0))
    }

    private static func swappedAdjacentLineBlocks(upperRange: NSRange, lowerRange: NSRange, in text: NSString) -> LineSwapOperation {
        let upperText = text.substring(with: upperRange)
        let lowerText = text.substring(with: lowerRange)
        let lowerEndsAtEOF = NSMaxRange(lowerRange) == text.length
        let lowerHasTrailingNewline = lowerText.hasSuffix("\n")

        let replacementText: String
        let movedBlockDelta: Int
        if lowerEndsAtEOF && !lowerHasTrailingNewline {
            let normalizedUpperText = upperText.hasSuffix("\n") ? String(upperText.dropLast()) : upperText
            replacementText = lowerText + "\n" + normalizedUpperText
            movedBlockDelta = lowerText.count + 1
        } else {
            replacementText = lowerText + upperText
            movedBlockDelta = lowerRange.length
        }

        return LineSwapOperation(
            replacedRange: NSRange(location: upperRange.location, length: NSMaxRange(lowerRange) - upperRange.location),
            replacementText: replacementText,
            upperSelectionLocationDelta: movedBlockDelta,
            lowerSelectionLocationDelta: -upperRange.length
        )
    }

    private static func commentEdits(in text: NSString, affectedRange: NSRange, syntaxLanguage: SyntaxLanguage) -> [CommentEdit] {
        let affectedEnd = NSMaxRange(affectedRange)
        var edits: [CommentEdit] = []
        var lineLocation = affectedRange.location
        let commentPrefix = lineCommentPrefix(for: syntaxLanguage)
        let prefixLength = (commentPrefix as NSString).length

        repeat {
            let lineRange = text.lineRange(for: NSRange(location: min(lineLocation, text.length), length: 0))
            let hasCommentPrefix = lineRange.location + prefixLength <= text.length
                && text.substring(with: NSRange(location: lineRange.location, length: prefixLength)) == commentPrefix

            edits.append(CommentEdit(
                location: lineRange.location,
                removedLength: hasCommentPrefix ? prefixLength : 0,
                insertedText: hasCommentPrefix ? "" : commentPrefix
            ))

            let nextLineLocation = NSMaxRange(lineRange)
            guard nextLineLocation > lineLocation else { break }
            lineLocation = nextLineLocation
        } while lineLocation < affectedEnd

        return edits
    }

    private static func transformedPosition(_ position: Int, byApplying edits: [CommentEdit]) -> Int {
        var delta = 0

        for edit in edits {
            if position < edit.location {
                break
            }

            if edit.removedLength > 0, position <= edit.location + edit.removedLength {
                return edit.location + delta + min(position - edit.location, edit.insertedLength)
            }

            delta += edit.insertedLength - edit.removedLength
        }

        return position + delta
    }

    private static func clampedRange(_ range: NSRange, toLength length: Int) -> NSRange {
        let safeLocation = min(max(range.location, 0), length)
        let safeLength = min(max(range.length, 0), max(length - safeLocation, 0))
        return NSRange(location: safeLocation, length: safeLength)
    }
}
