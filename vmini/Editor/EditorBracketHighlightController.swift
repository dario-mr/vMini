import AppKit

struct EditorBracketMatch {
    let range: NSRange
    let matchingRange: NSRange

    var highlightedRanges: [NSRange] {
        [range, matchingRange]
    }
}

enum EditorBracketMatching {
    private struct BracketPair {
        let opening: unichar
        let closing: unichar
    }

    private static let bracketPairs: [BracketPair] = [
        BracketPair(opening: 40, closing: 41),  // ()
        BracketPair(opening: 91, closing: 93),  // []
        BracketPair(opening: 123, closing: 125) // {}
    ]

    static func match(near selectedRange: NSRange, in text: NSString) -> EditorBracketMatch? {
        let clampedSelection = selectedRange.clamped(toLength: text.length)
        guard clampedSelection.length == 0 else {
            return nil
        }

        guard let candidate = candidateBracket(near: clampedSelection.location, in: text) else {
            return nil
        }

        let matchingLocation: Int?
        if candidate.character == candidate.pair.opening {
            matchingLocation = findClosingBracket(
                for: candidate.pair,
                startingAt: candidate.location + 1,
                in: text
            )
        } else {
            matchingLocation = findOpeningBracket(
                for: candidate.pair,
                startingAt: candidate.location - 1,
                in: text
            )
        }

        guard let matchingLocation else {
            return nil
        }

        return EditorBracketMatch(
            range: NSRange(location: candidate.location, length: 1),
            matchingRange: NSRange(location: matchingLocation, length: 1)
        )
    }

    private static func candidateBracket(
        near insertionLocation: Int,
        in text: NSString
    ) -> (location: Int, character: unichar, pair: BracketPair)? {
        let clampedLocation = min(max(insertionLocation, 0), text.length)

        if clampedLocation > 0,
           let candidate = bracketPair(for: text.character(at: clampedLocation - 1)) {
            return (clampedLocation - 1, text.character(at: clampedLocation - 1), candidate)
        }

        if clampedLocation < text.length,
           let candidate = bracketPair(for: text.character(at: clampedLocation)) {
            return (clampedLocation, text.character(at: clampedLocation), candidate)
        }

        return nil
    }

    private static func bracketPair(for character: unichar) -> BracketPair? {
        bracketPairs.first { $0.opening == character || $0.closing == character }
    }

    private static func findClosingBracket(
        for pair: BracketPair,
        startingAt location: Int,
        in text: NSString
    ) -> Int? {
        var nestingDepth = 0
        var scanLocation = location

        while scanLocation < text.length {
            let character = text.character(at: scanLocation)
            if character == pair.opening {
                nestingDepth += 1
            } else if character == pair.closing {
                if nestingDepth == 0 {
                    return scanLocation
                }
                nestingDepth -= 1
            }

            scanLocation += 1
        }

        return nil
    }

    private static func findOpeningBracket(
        for pair: BracketPair,
        startingAt location: Int,
        in text: NSString
    ) -> Int? {
        var nestingDepth = 0
        var scanLocation = location

        while scanLocation >= 0 {
            let character = text.character(at: scanLocation)
            if character == pair.closing {
                nestingDepth += 1
            } else if character == pair.opening {
                if nestingDepth == 0 {
                    return scanLocation
                }
                nestingDepth -= 1
            }

            scanLocation -= 1
        }

        return nil
    }
}

@MainActor
final class EditorBracketHighlightController {
    private let textView: NSTextView
    private let highlightColorProvider: () -> NSColor

    private var highlightedRanges: [NSRange] = []

    init(
        textView: NSTextView,
        highlightColorProvider: @escaping () -> NSColor
    ) {
        self.textView = textView
        self.highlightColorProvider = highlightColorProvider
    }

    func refresh() {
        clearHighlights()

        guard
            let layoutManager = textView.layoutManager,
            let match = EditorBracketMatching.match(
                near: textView.selectedRange(),
                in: textView.string as NSString
            )
        else {
            return
        }

        let highlightColor = highlightColorProvider()
        for range in match.highlightedRanges {
            layoutManager.addTemporaryAttributes([.backgroundColor: highlightColor], forCharacterRange: range)
        }
        highlightedRanges = match.highlightedRanges
    }

    private func clearHighlights() {
        guard let layoutManager = textView.layoutManager else {
            highlightedRanges = []
            return
        }

        for range in highlightedRanges {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        }
        highlightedRanges = []
    }
}
