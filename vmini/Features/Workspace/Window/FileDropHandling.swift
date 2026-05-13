import AppKit

@MainActor
protocol FileDropContentViewDelegate: AnyObject {
    func fileDropContentView(_ view: FileDropContentView, didReceiveFileSystemURLs urls: [URL])
}

final class FileDropContentView: NSView {
    weak var dropDelegate: FileDropContentViewDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.fileSystemURLs()
        guard !urls.isEmpty else { return false }

        dropDelegate?.fileDropContentView(self, didReceiveFileSystemURLs: urls)
        return true
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileSystemURLs().isEmpty ? [] : .copy
    }
}

final class FileDropTextView: NSTextView {
    private enum Navigation {
        static let homeKeyCode: UInt16 = 115
        static let endKeyCode: UInt16 = 119
        static let pageUpKeyCode: UInt16 = 116
        static let pageDownKeyCode: UInt16 = 121
        static let upArrowKeyCode: UInt16 = 126
        static let downArrowKeyCode: UInt16 = 125
    }

    var onFileSystemURLsDropped: (([URL]) -> Void)?
    var onMoveSelectedLinesUp: (() -> Bool)?
    var onMoveSelectedLinesDown: (() -> Bool)?

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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileSystemURLs().isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.fileSystemURLs().isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.fileSystemURLs()
        guard !urls.isEmpty else {
            return super.performDragOperation(sender)
        }

        onFileSystemURLsDropped?(urls)
        return true
    }

    @objc
    override func cancelOperation(_ sender: Any?) {
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

        layoutManager.ensureLayout(for: textContainer)

        let glyphIndex: Int
        if layoutManager.numberOfGlyphs == 0 {
            glyphIndex = 0
        } else {
            let characterIndex = min(referenceLocation, layoutManager.numberOfGlyphs - 1)
            glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
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

extension NSPasteboard {
    func fileSystemURLs() -> [URL] {
        let options: [ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]

        return readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { ($0 as? URL)?.standardizedFileURL } ?? []
    }
}

@MainActor
enum OpenURLRouter {
    static func open(_ urls: [URL], tabbedIn targetWindow: NSWindow?) {
        let folders = urls.filter(isDirectory)
        let files = urls.filter { !isDirectory($0) }

        OpenFoldersStore.shared.add(folders)
        WorkspaceDocumentCoordinator.shared.open(urls: files, activate: files.last)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
