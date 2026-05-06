import AppKit

final class LineNumberRulerView: NSView {
    private enum Constants {
        static let minThickness: CGFloat = 36
        static let horizontalPadding: CGFloat = 8
    }

    private weak var textView: NSTextView?
    var onRuleThicknessChanged: ((CGFloat) -> Void)?
    private(set) var ruleThickness = Constants.minThickness
    private var lineStarts: [Int] = [0]
    private let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }()

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        applyTheme()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var isOpaque: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    func invalidateLineNumbers() {
        rebuildLineCache()
        synchronizeRuleThickness()
        needsDisplay = true
    }

    func noteTextStorageDidEdit(_ textStorage: NSTextStorage, editedRange: NSRange, changeInLength: Int) {
        updateLineCache(
            text: textStorage.string as NSString,
            editedRange: editedRange,
            changeInLength: changeInLength
        )
        synchronizeRuleThickness()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return
        }

        AppColors.editorBackground.setFill()
        bounds.fill()

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else {
            drawLineNumber(
                1,
                atY: textView.textContainerInset.height - visibleRect.minY,
                lineHeight: textView.font?.boundingRectForFont.height ?? 16,
                isSelected: true
            )
            return
        }

        let selectedLineStart = selectedLineStart()
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var effectiveRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveRange,
                withoutAdditionalLayout: true
            )
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineStart = (textView.string as NSString).lineRange(
                for: NSRange(location: characterIndex, length: 0)
            ).location

            if characterIndex == lineStart {
                let lineNumber = lineNumber(forCharacterAt: characterIndex)
                drawLineNumber(
                    lineNumber,
                    atY: viewportY(forDocumentY: lineRect.minY + textView.textContainerOrigin.y),
                    lineHeight: lineRect.height,
                    isSelected: lineStart == selectedLineStart
                )
            }

            glyphIndex = NSMaxRange(effectiveRange)
        }

        drawTrailingLineNumberIfNeeded(
            layoutManager: layoutManager,
            textContainer: textContainer,
            selectedLineStart: selectedLineStart
        )
    }

    private func drawLineNumber(_ lineNumber: Int, atY y: CGFloat, lineHeight: CGFloat, isSelected: Bool) {
        if isSelected {
            AppColors.subtleSelectionFill.setFill()
            NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont(),
            .foregroundColor: isSelected ? AppColors.sidebarHeaderText : AppColors.lineNumberText,
            .paragraphStyle: paragraphStyle,
        ]
        let string = "\(lineNumber)" as NSString
        let size = string.size(withAttributes: attributes)
        let drawRect = NSRect(
            x: 0,
            y: y,
            width: ruleThickness - Constants.horizontalPadding,
            height: size.height
        )
        string.draw(in: drawRect, withAttributes: attributes)
    }

    private func selectedLineStart() -> Int {
        guard let textView else {
            return 0
        }

        let text = textView.string as NSString
        let selectedLocation = min(textView.selectedRange().location, text.length)
        return text.lineRange(for: NSRange(location: selectedLocation, length: 0)).location
    }

    private func lineNumberFont() -> NSFont {
        let fontSize = textView?.font?.pointSize ?? 13
        return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
    }

    private func drawTrailingLineNumberIfNeeded(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        selectedLineStart: Int
    ) {
        guard let textView else {
            return
        }

        let string = textView.string as NSString
        let needsTrailingLineNumber = string.length == 0 || string.hasSuffix("\n")
        guard needsTrailingLineNumber else {
            return
        }

        let extraLineRect = layoutManager.extraLineFragmentRect
        guard !extraLineRect.isEmpty else {
            return
        }

        let lineNumber = lineNumber(forCharacterAt: string.length)

        drawLineNumber(
            lineNumber,
            atY: viewportY(forDocumentY: extraLineRect.minY + textView.textContainerOrigin.y),
            lineHeight: extraLineRect.height,
            isSelected: selectedLineStart == string.length
        )
    }

    private func viewportY(forDocumentY documentY: CGFloat) -> CGFloat {
        guard let textView else {
            return documentY
        }

        return documentY - textView.visibleRect.minY
    }

    private func lineNumber(forCharacterAt characterIndex: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= characterIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(low, 1)
    }

    private func rebuildLineCache() {
        guard let text = textView?.string else {
            lineStarts = [0]
            return
        }

        lineStarts = Self.allLineStarts(in: text as NSString)
    }

    private func updateLineCache(text: NSString, editedRange: NSRange, changeInLength: Int) {
        guard !lineStarts.isEmpty else {
            lineStarts = Self.allLineStarts(in: text)
            return
        }

        guard changeInLength >= 0, editedRange.length == changeInLength else {
            lineStarts = Self.allLineStarts(in: text)
            return
        }

        let lineIndex = lineIndex(containing: editedRange.location)
        let preservedPrefix = Array(lineStarts.prefix(lineIndex + 1))

        let oldNextLineIndex = firstLineIndex(startingAfter: editedRange.location)
        let oldNextLineStart = oldNextLineIndex < lineStarts.count ? lineStarts[oldNextLineIndex] : nil

        let newNextLineStart = oldNextLineStart.map { $0 + changeInLength } ?? text.length
        let scannedRange = NSRange(
            location: editedRange.location,
            length: max(newNextLineStart - editedRange.location, 0)
        )

        var replacementStarts = Self.lineStarts(in: text, range: scannedRange)
        if replacementStarts.first == preservedPrefix.last {
            replacementStarts.removeFirst()
        }

        let shiftedSuffix: [Int]
        if oldNextLineIndex < lineStarts.count {
            shiftedSuffix = lineStarts[oldNextLineIndex...].map { $0 + changeInLength }
        } else {
            shiftedSuffix = []
        }

        lineStarts = Self.uniquedLineStarts(preservedPrefix + replacementStarts + shiftedSuffix)
        if lineStarts.isEmpty || lineStarts[0] != 0 {
            lineStarts.insert(0, at: 0)
        }
    }

    private func synchronizeRuleThickness() {
        let lineCount = max(1, lineStarts.count)
        let digitCount = "\(lineCount)".count
        let digitWidth = "0".size(withAttributes: [
            .font: lineNumberFont(),
        ]).width
        let requiredThickness = max(Constants.minThickness, ceil(CGFloat(digitCount) * digitWidth + Constants.horizontalPadding * 2))
        if abs(ruleThickness - requiredThickness) > 0.5 {
            ruleThickness = requiredThickness
            onRuleThicknessChanged?(requiredThickness)
        }
    }

    private func lineIndex(containing location: Int) -> Int {
        max(lineNumber(forCharacterAt: location) - 1, 0)
    }

    private func firstLineIndex(startingAtOrAfter location: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] < location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func firstLineIndex(startingAfter location: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func allLineStarts(in text: NSString) -> [Int] {
        uniquedLineStarts([0] + lineStarts(in: text, range: NSRange(location: 0, length: text.length)))
    }

    private static func lineStarts(in text: NSString, range: NSRange) -> [Int] {
        guard range.length > 0 else {
            return []
        }

        var starts: [Int] = []
        var searchLocation = range.location
        let rangeEnd = NSMaxRange(range)
        while searchLocation < rangeEnd {
            let newlineRange = text.range(
                of: "\n",
                options: [],
                range: NSRange(location: searchLocation, length: rangeEnd - searchLocation)
            )
            guard newlineRange.location != NSNotFound else {
                break
            }

            let nextLineStart = newlineRange.location + newlineRange.length
            if nextLineStart <= text.length {
                starts.append(nextLineStart)
            }
            searchLocation = nextLineStart
        }

        return starts
    }

    private static func uniquedLineStarts(_ starts: [Int]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(starts.count)
        for start in starts where result.last != start {
            result.append(start)
        }
        return result
    }

    @objc
    private func handleThemeDidChange() {
        applyTheme()
        needsDisplay = true
    }

    private func applyTheme() {
        layer?.backgroundColor = AppColors.editorBackground.cgColor
    }
}
