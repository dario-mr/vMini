import AppKit

class EditorTextView: NSTextView {
    private static let selectionDelimiters = [
        "`": "`", "'": "'", "\"": "\"",
        "(": ")", "[": "]", "{": "}",
        "*": "*", "_": "_", "~": "~",
    ]

    private enum Navigation {
        static let homeKeyCode: UInt16 = 115
        static let endKeyCode: UInt16 = 119
        static let pageUpKeyCode: UInt16 = 116
        static let pageDownKeyCode: UInt16 = 121
        static let upArrowKeyCode: UInt16 = 126
        static let downArrowKeyCode: UInt16 = 125
    }

    var onCancelSearch: (() -> Bool)?
    var onNavigationCheckpoint: ((NSRange, NSRange) -> Void)?
    var onIndentSelectedLines: (() -> Bool)?
    var onMoveSelectedLinesUp: (() -> Bool)?
    var onMoveSelectedLinesDown: (() -> Bool)?
    var onCommandClick: ((Int) -> Bool)?
    var isCommandClickTarget: ((Int) -> Bool)?
    private var linkTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let linkTrackingArea { removeTrackingArea(linkTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self
        )
        addTrackingArea(area)
        linkTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        // NSTextView's handler can briefly restore the I-beam before our link cursor.
        updateLinkCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateLinkCursor(at: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point) else { return }
        updateLinkCursor(at: point, modifiers: event.modifierFlags)
    }

    private func updateLinkCursor(at point: NSPoint, modifiers: NSEvent.ModifierFlags) {
        let isLink = modifiers.contains(.command)
            && characterIndex(at: point).map { isCommandClickTarget?($0) == true } == true
        let cursor = isLink ? NSCursor.pointingHand : NSCursor.iBeam
        if NSCursor.current != cursor { cursor.set() }
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(containerPoint) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    override func mouseDown(with event: NSEvent) {
        let previousSelection = selectedRange()
        defer { onNavigationCheckpoint?(previousSelection, selectedRange()) }
        if event.modifierFlags.contains(.command),
           let index = characterIndex(at: convert(event.locationInWindow, from: nil)),
           onCommandClick?(index) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let selection = selectedRange()
        guard replacementRange.location == NSNotFound, !hasMarkedText(),
              selectedRanges.count == 1, selection.length > 0,
              let opening = insertString as? String, let closing = Self.selectionDelimiters[opening] else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let text = string as NSString
        let wrappedLength = text.length + 2
        let wrapped = opening + text.substring(with: selection) + closing
        super.insertText(wrapped, replacementRange: selection)
        if (string as NSString).length == wrappedLength {
            setSelectedRange(NSRange(location: selection.location + 1, length: selection.length))
        }
    }

    @objc
    override func insertTab(_ sender: Any?) {
        guard selectedRange().length > 0 else {
            super.insertTab(sender)
            return
        }

        _ = onIndentSelectedLines?()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let previousSelection = selectedRange()
        let isNavigation = [Navigation.homeKeyCode, Navigation.endKeyCode,
                            Navigation.pageUpKeyCode, Navigation.pageDownKeyCode].contains(event.keyCode)
            || (modifiers.contains(.command)
                && [Navigation.upArrowKeyCode, Navigation.downArrowKeyCode].contains(event.keyCode))
        defer {
            if isNavigation { onNavigationCheckpoint?(previousSelection, selectedRange()) }
        }

        if modifiers.contains([.option, .shift]) && !modifiers.contains(.command) && !modifiers.contains(.control) {
            switch event.keyCode {
            case Navigation.upArrowKeyCode:
                if onMoveSelectedLinesUp?() == true {
                    return
                }
            case Navigation.downArrowKeyCode:
                if onMoveSelectedLinesDown?() == true {
                    return
                }
            default:
                break
            }
        }

        if modifiers.isEmpty {
            switch event.keyCode {
            case Navigation.homeKeyCode:
                moveToBeginningOfLine(nil)
                return
            case Navigation.endKeyCode:
                moveToEndOfLine(nil)
                return
            case Navigation.pageUpKeyCode:
                pageUp(nil)
                return
            case Navigation.pageDownKeyCode:
                pageDown(nil)
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }

    @objc
    override func cancelOperation(_ sender: Any?) {
        if onCancelSearch?() == true { return }
        let currentSelection = selectedRange()
        guard currentSelection.length > 0 else {
            return
        }

        setSelectedRange(NSRange(location: NSMaxRange(currentSelection), length: 0))
        scrollRangeToVisible(selectedRange())
    }

    @objc
    override func moveToBeginningOfDocument(_ sender: Any?) {
        completePendingTypingCommand()
        super.moveToBeginningOfDocument(sender)
    }

    @objc
    override func moveToEndOfDocument(_ sender: Any?) {
        completePendingTypingCommand()
        super.moveToEndOfDocument(sender)
    }

    @objc
    override func pageUp(_ sender: Any?) {
        completePendingTypingCommand()
        moveCaretByPage(direction: -1)
    }

    @objc
    override func pageDown(_ sender: Any?) {
        completePendingTypingCommand()
        moveCaretByPage(direction: 1)
    }

    @objc
    override func scrollPageUp(_ sender: Any?) {
        completePendingTypingCommand()
        moveCaretByPage(direction: -1)
    }

    @objc
    override func scrollPageDown(_ sender: Any?) {
        completePendingTypingCommand()
        moveCaretByPage(direction: 1)
    }

    @objc
    override func scrollToBeginningOfDocument(_ sender: Any?) {
        completePendingTypingCommand()
        moveToBeginningOfLine(sender)
    }

    @objc
    override func scrollToEndOfDocument(_ sender: Any?) {
        completePendingTypingCommand()
        moveToEndOfLine(sender)
    }

    private func completePendingTypingCommand() {
        inputContext?.discardMarkedText()
    }

    private func moveCaretByPage(direction: CGFloat) {
        guard let layoutManager, let textContainer else { return }

        let textLength = string.utf16.count
        let currentSelection = selectedRange()
        let insertionLocation = min(currentSelection.location, textLength)
        let referenceLocation = max(0, min(insertionLocation, max(textLength - 1, 0)))

        let visibleContainerRect = visibleRect.offsetBy(
            dx: -textContainerOrigin.x,
            dy: -textContainerOrigin.y
        )
        let destinationRect = visibleContainerRect.offsetBy(
            dx: 0,
            dy: visibleContainerRect.height * direction
        )
        layoutManager.ensureLayout(
            forBoundingRect: visibleContainerRect.union(destinationRect),
            in: textContainer
        )

        let glyphIndex: Int
        if textLength == 0 {
            glyphIndex = 0
        } else {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: referenceLocation)
        }

        var lineRange = NSRange(location: 0, length: 0)
        let lineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &lineRange,
            withoutAdditionalLayout: true
        )

        let targetPoint = NSPoint(
            x: leadingCaretX(for: textContainer),
            y: lineRect.midY + (visibleRect.height * direction)
        )
        let targetIndex = characterIndexForInsertion(at: targetPoint)
        setSelectedRange(NSRange(location: min(targetIndex, textLength), length: 0))
        scrollRangeToVisible(selectedRange())
    }

    private func leadingCaretX(for textContainer: NSTextContainer) -> CGFloat {
        textContainerInset.width + textContainer.lineFragmentPadding
    }
}
