import Foundation

enum PendingSyntaxHighlight: Equatable {
    case none
    case range(NSRange, textLength: Int)
    case full

    var isEmpty: Bool {
        if case .none = self { return true }
        return false
    }

    mutating func adjust(for editContext: SyntaxHighlightEditContext?, currentTextLength: Int) {
        guard case .range(let range, let textLength) = self else { return }
        guard let editContext,
              let adjustedRange = adjusted(range, through: editContext, currentTextLength: currentTextLength),
              textLength == currentTextLength
                - (editContext.replacementString as NSString).length
                + (editContext.replacedText as NSString).length else {
            self = .full
            return
        }
        self = .range(adjustedRange, textLength: currentTextLength)
    }

    mutating func merge(_ incomingRange: NSRange, textLength: Int) {
        let incomingRange = incomingRange.clamped(toLength: textLength)
        if incomingRange.location == 0, incomingRange.length == textLength {
            self = .full
            return
        }

        switch self {
        case .none:
            self = .range(incomingRange, textLength: textLength)
        case .range(let existingRange, _):
            self = .range(NSUnionRange(existingRange, incomingRange), textLength: textLength)
        case .full:
            break
        }
    }

    private func adjusted(
        _ range: NSRange,
        through editContext: SyntaxHighlightEditContext,
        currentTextLength: Int
    ) -> NSRange? {
        let editRange = editContext.replacementRange
        let replacedLength = (editContext.replacedText as NSString).length
        let replacementLength = (editContext.replacementString as NSString).length
        let oldLength = currentTextLength - replacementLength + replacedLength
        guard editRange.length == replacedLength,
              editRange.location <= oldLength,
              editRange.upperBound <= oldLength else {
            return nil
        }

        let delta = replacementLength - replacedLength
        if range.upperBound <= editRange.location {
            return range.clamped(toLength: currentTextLength)
        }
        if range.location >= editRange.upperBound {
            return NSRange(location: range.location + delta, length: range.length)
                .clamped(toLength: currentTextLength)
        }

        let start = min(range.location, editRange.location)
        let end = max(
            range.upperBound > editRange.upperBound ? range.upperBound + delta : editRange.location + replacementLength,
            editRange.location + replacementLength
        )
        return NSRange(location: start, length: max(end - start, 0)).clamped(toLength: currentTextLength)
    }
}
