import AppKit

@MainActor
final class EditorSelectionOccurrenceController {
    var isEnabled = true { didSet { refresh() } }
    private let textView: EditorTextView
    private let highlightColorProvider: () -> NSColor
    private var pendingRefreshTask: Task<Void, Never>?

    init(textView: EditorTextView, highlightColorProvider: @escaping () -> NSColor) {
        self.textView = textView
        self.highlightColorProvider = highlightColorProvider
    }

    deinit {
        pendingRefreshTask?.cancel()
    }

    func handleTextStorageDidEdit() {
        pendingRefreshTask?.cancel()
        clearHighlights()
        // Layout still has the old glyph ranges inside NSTextStorage's editing callback.
        pendingRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
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
            guard !Task.isCancelled, let self else { return }

            let otherOccurrences = ranges.filter { NSIntersectionRange($0, selection).length == 0 }
            self.textView.setSelectionOccurrenceHighlights(
                otherOccurrences,
                color: otherOccurrences.isEmpty ? nil : self.highlightColorProvider()
            )
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
        textView.setSelectionOccurrenceHighlights([], color: nil)
    }
}
