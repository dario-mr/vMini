import Foundation

enum MarkdownListContinuation {
    private static let markerPattern = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-+*])|([0-9]+)([.)]))([ \t]+|$)"#)

    static func indentEdit(in text: NSString, selectedRange: NSRange) -> EditorTextEdit? {
        guard let (contentRange, line, match) = emptyItem(in: text, selectedRange: selectedRange) else { return nil }

        let indentation = line.substring(with: match.range(at: 1))
        let marker = match.range(at: 3).location == NSNotFound
            ? line.substring(with: match.range(at: 2))
            : "1" + line.substring(with: match.range(at: 4))
        let indentWidth = max(4, match.range.length - match.range(at: 1).length)
        let replacement = indentation + String(repeating: " ", count: indentWidth)
            + marker + line.substring(with: match.range(at: 5))
        return EditorTextEdit(
            replacementRange: contentRange,
            replacementText: replacement,
            selectedRange: NSRange(location: contentRange.location + replacement.utf16.count, length: 0)
        )
    }

    static func deleteBackwardEdit(in text: NSString, selectedRange: NSRange) -> EditorTextEdit? {
        guard let (contentRange, line, match) = emptyItem(in: text, selectedRange: selectedRange) else { return nil }
        let indentation = line.substring(with: match.range(at: 1))
        let trailingSpaces = indentation.reversed().prefix { $0 == " " }.count
        let indentWidth = max(4, match.range.length - match.range(at: 1).length)
        var remainingIndent = String(indentation.dropLast(trailingSpaces == 0 ? 1 : min(trailingSpaces, indentWidth)))

        var location = contentRange.location
        while location > 0, !indentation.isEmpty, !indentation.contains("\t") {
            let previousRange = text.lineRange(for: NSRange(location: location - 1, length: 0))
            let previousLine = text.substring(with: previousRange) as NSString
            location = previousRange.location
            guard let previousMatch = markerPattern.firstMatch(in: previousLine as String, range: NSRange(location: 0, length: previousLine.length)) else { continue }
            let parentIndent = previousLine.substring(with: previousMatch.range(at: 1))
            guard parentIndent.utf16.count < indentation.utf16.count, indentation.hasPrefix(parentIndent) else { continue }
            // A continued number can gain a digit before Tab restarts it at 1.
            let parentWidth = max(4, previousMatch.range.length - parentIndent.utf16.count + 1)
            if indentation.utf16.count - parentIndent.utf16.count <= parentWidth {
                remainingIndent = parentIndent
            }
            break
        }

        let replacement = indentation.isEmpty ? "" : remainingIndent + line.substring(from: match.range(at: 1).length)
        return EditorTextEdit(
            replacementRange: contentRange,
            replacementText: replacement,
            selectedRange: NSRange(location: contentRange.location + replacement.utf16.count, length: 0)
        )
    }

    static func newlineEdit(in text: NSString, selectedRange: NSRange) -> EditorTextEdit? {
        let selection = selectedRange.clamped(toLength: text.length)
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        guard let contentRange = MarkdownFenceCache.visibleLineContentsRange(for: lineRange, text: text),
              selection.upperBound <= contentRange.upperBound else { return nil }

        let line = text.substring(with: contentRange) as NSString
        guard let match = markerPattern.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)),
              selection.location >= lineRange.location + match.range.length else { return nil }

        let compact = (line as String).filter { !$0.isWhitespace }
        if compact.count >= 3, let first = compact.first, ["-", "*"].contains(first),
           compact.allSatisfy({ $0 == first }) { return nil }
        guard !MarkdownFenceCache.makeFenceCache(in: text).blocks.contains(where: {
            NSLocationInRange(lineRange.location, $0.totalRange)
        }) else { return nil }

        let indentation = line.substring(with: match.range(at: 1))
        let content = line.substring(from: match.range.length)
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            return EditorTextEdit(
                replacementRange: contentRange,
                replacementText: indentation,
                selectedRange: NSRange(location: lineRange.location + indentation.utf16.count, length: 0)
            )
        }

        let marker: String
        if match.range(at: 3).location != NSNotFound {
            guard let number = Int(line.substring(with: match.range(at: 3))), number < Int.max else { return nil }
            marker = "\(number + 1)" + line.substring(with: match.range(at: 4))
        } else {
            marker = "-"
        }
        let replacement = "\n" + indentation + marker + line.substring(with: match.range(at: 5))
        return EditorTextEdit(
            replacementRange: selection,
            replacementText: replacement,
            selectedRange: NSRange(location: selection.location + replacement.utf16.count, length: 0)
        )
    }

    private static func emptyItem(in text: NSString, selectedRange: NSRange) -> (NSRange, NSString, NSTextCheckingResult)? {
        let selection = selectedRange.clamped(toLength: text.length)
        let lineRange = text.lineRange(for: selection)
        guard selection.length == 0,
              let contentRange = MarkdownFenceCache.visibleLineContentsRange(for: lineRange, text: text),
              selection.location == contentRange.upperBound else { return nil }
        let line = text.substring(with: contentRange) as NSString
        guard let match = markerPattern.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)),
              match.range.length == line.length,
              !MarkdownFenceCache.makeFenceCache(in: text).blocks.contains(where: {
                  NSLocationInRange(lineRange.location, $0.totalRange)
              }) else { return nil }
        return (contentRange, line, match)
    }
}
