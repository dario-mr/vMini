import AppKit

enum EditorSearchAction: Int {
    case find, replace, next, previous, close

    static func action(for event: NSEvent) -> Self? {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f": return .find
            case "r": return .replace
            default: return nil
            }
        }
        guard modifiers.isEmpty else { return nil }
        switch event.keyCode {
        case 99: return .next // F3
        case 120: return .previous // F2
        case 53: return .close
        default: return nil
        }
    }
}

@MainActor
final class EditorSearchController: NSObject, NSTextFieldDelegate {
    private static let marker = NSAttributedString.Key("vmini.searchOccurrence")
    let panel = EditorSearchPanel()
    private let textView: NSTextView
    private(set) var matches: [NSRange] = []
    var onVisibilityChanged: ((Bool) -> Void)?
    var onNavigationCheckpoint: ((NSRange, NSRange) -> Void)?
    var isVisible: Bool { !panel.isHidden }

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
        panel.searchField.delegate = self
        panel.replacementField.delegate = self
        for (button, action) in [
            (panel.previousButton, #selector(previous)), (panel.nextButton, #selector(next)),
            (panel.closeButton, #selector(close)), (panel.replaceButton, #selector(replace)),
            (panel.replaceAllButton, #selector(replaceAll)),
        ] {
            button.target = self
            button.action = action
        }
    }

    @discardableResult
    func perform(_ action: EditorSearchAction) -> Bool {
        switch action {
        case .find: show(replacement: false)
        case .replace: show(replacement: true)
        case .next, .previous:
            if !isVisible {
                reveal(replacement: false)
                panel.window?.makeFirstResponder(panel.searchField)
            }
            navigate(backwards: action == .previous)
        case .close:
            guard isVisible else { return false }
            close()
        }
        return true
    }

    func show(replacement: Bool) {
        let selection = textView.selectedRange().clamped(toLength: (textView.string as NSString).length)
        if selection.length > 0 {
            panel.searchField.stringValue = (textView.string as NSString).substring(with: selection)
        }
        reveal(replacement: replacement)
        selectMatch(at: matches.firstIndex { $0.location >= selection.location } ?? (matches.isEmpty ? nil : 0))
        panel.window?.makeFirstResponder(panel.searchField)
        panel.searchField.selectText(nil)
    }

    private func reveal(replacement: Bool) {
        panel.show(replacement: replacement)
        onVisibilityChanged?(true)
        refresh()
    }

    @objc func close() {
        clearHighlights()
        panel.close()
        matches = []
        onVisibilityChanged?(false)
        textView.window?.makeFirstResponder(textView)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === panel.searchField else { return }
        refresh()
        let location = textView.selectedRange().location
        selectMatch(at: matches.firstIndex { $0.location >= location } ?? (matches.isEmpty ? nil : 0))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            let field = panel.showsReplacement && control === panel.searchField ? panel.replacementField : panel.searchField
            panel.window?.makeFirstResponder(field)
            field.selectText(nil)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            close()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === panel.replacementField { replace() } else { next() }
            return true
        }
        return false
    }

    nonisolated static func matchingRanges(in string: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let text = string as NSString
        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            let match = text.range(of: query, options: [.caseInsensitive, .literal], range: NSRange(location: location, length: text.length - location))
            guard match.location != NSNotFound else { break }
            ranges.append(match)
            location = NSMaxRange(match)
        }
        return ranges
    }

    func refresh() {
        guard isVisible else { return }
        clearHighlights()
        matches = Self.matchingRanges(in: textView.string, query: panel.searchField.stringValue)
        let color = NSColor.systemYellow.withAlphaComponent(0.32)
        for range in matches {
            textView.layoutManager?.addTemporaryAttributes([.backgroundColor: color, Self.marker: true], forCharacterRange: range)
        }
        selectionDidChange()
    }

    func selectionDidChange() {
        guard isVisible else { return }
        panel.updateCount(current: matches.firstIndex(of: textView.selectedRange()), total: matches.count)
    }

    @objc func next() { navigate(backwards: false) }
    @objc func previous() { navigate(backwards: true) }

    private func navigate(backwards: Bool) {
        guard !matches.isEmpty else { return }
        let selection = textView.selectedRange()
        let index: Int
        if let current = matches.firstIndex(of: selection) {
            index = (current + (backwards ? matches.count - 1 : 1)) % matches.count
        } else if backwards {
            index = matches.lastIndex { $0.location < selection.location } ?? matches.count - 1
        } else {
            index = matches.firstIndex { $0.location >= NSMaxRange(selection) } ?? 0
        }
        selectMatch(at: index)
    }

    private func selectMatch(at index: Int?) {
        guard let index else { selectionDidChange(); return }
        let previousSelection = textView.selectedRange()
        textView.setSelectedRange(matches[index])
        textView.scrollRangeToVisible(matches[index])
        selectionDidChange()
        onNavigationCheckpoint?(previousSelection, matches[index])
    }

    @objc func replace() {
        guard isVisible, !matches.isEmpty else { return }
        if !matches.contains(textView.selectedRange()) { next() }
        let range = textView.selectedRange()
        let replacement = panel.replacementField.stringValue
        textView.insertText(replacement, replacementRange: range)
        refresh()
        let end = range.location + (replacement as NSString).length
        selectMatch(at: matches.firstIndex { $0.location >= end } ?? (matches.isEmpty ? nil : 0))
    }

    @objc func replaceAll() {
        guard isVisible, !matches.isEmpty, let storage = textView.textStorage else { return }
        let ranges = matches
        let replacement = panel.replacementField.stringValue
        guard textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: Array(repeating: replacement, count: ranges.count)) else { return }
        storage.beginEditing()
        for range in ranges.reversed() { storage.replaceCharacters(in: range, with: replacement) }
        storage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: ranges[0].location, length: (replacement as NSString).length))
        refresh()
    }

    private func clearHighlights() {
        guard let layout = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        var location = 0
        // Temporary attributes follow edits, so clear using their current positions.
        while location < length {
            var range = NSRange()
            let attributes = layout.temporaryAttributes(atCharacterIndex: location, effectiveRange: &range)
            if attributes[Self.marker] != nil {
                layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range.clamped(toLength: length))
                layout.removeTemporaryAttribute(Self.marker, forCharacterRange: range.clamped(toLength: length))
            }
            location = max(location + 1, NSMaxRange(range))
        }
    }
}
