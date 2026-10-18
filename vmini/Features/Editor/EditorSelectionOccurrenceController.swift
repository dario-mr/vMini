import AppKit

@MainActor
final class EditorSelectionOccurrenceController {
    private static let marker = NSAttributedString.Key("vmini.selectionOccurrence")

    var isEnabled = true { didSet { refresh() } }
    private let textView: NSTextView
    private let highlightColorProvider: () -> NSColor
    private var pendingRefreshTask: Task<Void, Never>?
    private var hasHighlights = false

    init(textView: NSTextView, highlightColorProvider: @escaping () -> NSColor) {
        self.textView = textView
        self.highlightColorProvider = highlightColorProvider
    }

    deinit {
        pendingRefreshTask?.cancel()
    }

    func refresh() {
        pendingRefreshTask?.cancel()
        clearHighlights()
        guard isEnabled else { return }

        guard textView.selectedRanges.count == 1 else { return }
        let selection = textView.selectedRange()
        let snapshot = textView.string
        guard Self.selectedText(in: snapshot as NSString, selection: selection) != nil else { return }

        pendingRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 75_000_000)
            } catch {
                return
            }
            let work = Task.detached(priority: .userInitiated) {
                Self.matchingRanges(in: snapshot, selection: selection)
            }
            let ranges = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            guard !Task.isCancelled, let self, let layoutManager = textView.layoutManager else { return }

            let attributes: [NSAttributedString.Key: Any] = [
                .backgroundColor: highlightColorProvider(),
                Self.marker: true,
            ]
            for range in ranges {
                layoutManager.addTemporaryAttributes(attributes, forCharacterRange: range)
            }
            hasHighlights = !ranges.isEmpty
        }
    }

    nonisolated static func matchingRanges(in string: String, selection: NSRange) -> [NSRange] {
        let text = string as NSString
        guard let selectedText = selectedText(in: text, selection: selection) else { return [] }
        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            guard !Task.isCancelled else { return [] }
            let match = text.range(of: selectedText, options: .literal, range: NSRange(location: location, length: text.length - location))
            guard match.location != NSNotFound else { break }
            ranges.append(match)
            location = NSMaxRange(match)
        }
        return ranges
    }

    nonisolated private static func selectedText(in text: NSString, selection: NSRange) -> String? {
        guard selection.location >= 0, selection.location <= text.length,
              selection.length > 0, selection.length <= text.length - selection.location else { return nil }
        let selectedText = text.substring(with: selection)
        return selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selectedText
    }

    private func clearHighlights() {
        guard hasHighlights, let layoutManager = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        var location = 0
        // Temporary attributes move with edits; stored ranges would leave shifted highlights behind.
        while location < length {
            var range = NSRange()
            let attributes = layoutManager.temporaryAttributes(atCharacterIndex: location, effectiveRange: &range)
            if attributes[Self.marker] != nil {
                let validRange = range.clamped(toLength: length)
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: validRange)
                layoutManager.removeTemporaryAttribute(Self.marker, forCharacterRange: validRange)
            }
            location = max(location + 1, NSMaxRange(range))
        }
        hasHighlights = false
    }
}
