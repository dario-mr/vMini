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
    var onIndentSelectedLines: (() -> Bool)?
    var onMoveSelectedLinesUp: (() -> Bool)?
    var onMoveSelectedLinesDown: (() -> Bool)?

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
