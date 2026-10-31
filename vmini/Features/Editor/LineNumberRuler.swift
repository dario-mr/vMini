import AppKit

final class LineNumberRulerView: NSView {
    private enum Constants {
        static let minThickness: CGFloat = 42
        static let horizontalPadding: CGFloat = 14
        static let editedLineMarkerWidth: CGFloat = 2
    }

    private weak var textView: NSTextView?
    private var savedText = ""
    private var editedLineStarts = Set<Int>()
    var onRuleThicknessChanged: ((CGFloat) -> Void)?
    private(set) var ruleThickness = Constants.minThickness
    private var lineIndex = EditorLineIndex()
    private let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }()
    private var themeObservation: ObservationToken?
    private var cachedLineNumberFont: NSFont?
    private var cachedLineNumberFontPointSize: CGFloat = 0
    private var cachedDigitWidth: CGFloat = 0
    private var cachedSelectedAttributes: [NSAttributedString.Key: Any]?
    private var cachedUnselectedAttributes: [NSAttributedString.Key: Any]?
    private var lastSelectedLineStart = 0

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        applyTheme()

        themeObservation = ThemeManager.shared.observe { [weak self] _ in
            self?.handleThemeDidChange()
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    func invalidateLineNumbers() {
        synchronizeRuleThickness()
        lastSelectedLineStart = selectedLineStart()
        needsDisplay = true
    }

    func resetLineCache() {
        AppPerformanceProfiler.measure("LineNumberCacheBuild") {
            lineIndex.reset(text: (textView?.string ?? "") as NSString)
        }
        savedText = textView?.string ?? ""
        editedLineStarts.removeAll()
        invalidateLineNumbers()
    }

    func noteTextStorageDidEdit(_ textStorage: NSTextStorage, editedRange: NSRange, changeInLength: Int) {
        let text = textStorage.string as NSString
        AppPerformanceProfiler.measure("LineNumberCacheUpdate") {
            lineIndex.update(
                text: text,
                editedRange: editedRange,
                changeInLength: changeInLength
            )
        }
        editedLineStarts = Set(
            Self.editedLineIndexes(currentText: text as String, savedText: savedText)
                .map { lineIndex.lineStarts[$0] }
        )
        synchronizeRuleThickness()
        lastSelectedLineStart = selectedLineStart()
        needsDisplay = true
    }

    func markChangesSaved() {
        savedText = textView?.string ?? ""
        editedLineStarts.removeAll()
        needsDisplay = true
    }

    func hasUnsavedChanges(onLine lineNumber: Int) -> Bool {
        guard lineIndex.lineStarts.indices.contains(lineNumber - 1) else { return false }
        return editedLineStarts.contains(lineIndex.lineStarts[lineNumber - 1])
    }

    static func editedLineIndexes(currentText: String, savedText: String) -> Set<Int> {
        let currentLines = currentText.components(separatedBy: "\n")
        let savedLines = savedText.components(separatedBy: "\n")
        return Set(currentLines.difference(from: savedLines).compactMap { change in
            let lineIndex: Int
            switch change {
            case let .insert(offset, _, _):
                lineIndex = offset
            case let .remove(offset, _, _):
                lineIndex = min(offset, currentLines.count - 1)
            }
            return (0..<currentLines.count).contains(lineIndex) ? lineIndex : nil
        })
    }

    func currentCursorPosition() -> EditorCursorPosition {
        guard let textView else {
            return EditorCursorPosition(line: 1, column: 1)
        }

        let text = textView.string as NSString
        let selectedLocation = min(textView.selectedRange().location, text.length)
        let selectedLineIndex = lineIndex.index(containing: selectedLocation)
        let lineStart = lineIndex.lineStarts.indices.contains(selectedLineIndex) ? lineIndex.lineStarts[selectedLineIndex] : 0
        let prefixRange = NSRange(location: lineStart, length: max(selectedLocation - lineStart, 0))
        let column = text.substring(with: prefixRange).count + 1
        return EditorCursorPosition(line: selectedLineIndex + 1, column: column)
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
        layoutManager.ensureLayout(forBoundingRect: visibleRect, in: textContainer)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else {
            drawLineNumber(
                1,
                atY: textView.textContainerInset.height - visibleRect.minY,
                lineHeight: lineNumberFont().boundingRectForFont.height,
                isSelected: true
            )
            return
        }

        let selectedLineStart = selectedLineStart()
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange), glyphIndex < layoutManager.numberOfGlyphs {
            var effectiveRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveRange,
                withoutAdditionalLayout: false
            )
            guard effectiveRange.location != NSNotFound, NSMaxRange(effectiveRange) > glyphIndex else { break }
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let text = textView.string as NSString
            // Undo can leave glyph positions outside the shortened text while layout catches up.
            guard characterIndex >= 0, characterIndex < text.length else { break }
            let lineStart = text.lineRange(
                for: NSRange(location: characterIndex, length: 0)
            ).location

            if characterIndex == lineStart {
                let lineNumber = lineIndex.lineNumber(forCharacterAt: characterIndex)
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

        if hasUnsavedChanges(onLine: lineNumber) {
            AppColors.primaryActionBackground.setFill()
            NSRect(
                x: ruleThickness - Constants.horizontalPadding
                    + (Constants.horizontalPadding - Constants.editedLineMarkerWidth) / 2,
                y: y,
                width: Constants.editedLineMarkerWidth,
                height: lineHeight
            ).fill()
        }

        let attributes = lineNumberAttributes(isSelected: isSelected)
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
        let pointSize = EditorSettings.currentFontSize()
        if let cachedLineNumberFont, abs(pointSize - cachedLineNumberFontPointSize) < 0.5 {
            return cachedLineNumberFont
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .light)
        cachedLineNumberFont = font
        cachedLineNumberFontPointSize = pointSize
        cachedDigitWidth = "0".size(withAttributes: [.font: font]).width
        cachedSelectedAttributes = nil
        cachedUnselectedAttributes = nil
        return font
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

        let lineNumber = lineIndex.lineNumber(forCharacterAt: string.length)

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

    private func synchronizeRuleThickness() {
        _ = lineNumberFont()
        let lineCount = max(1, lineIndex.lineStarts.count)
        let digitCount = "\(lineCount)".count
        let requiredThickness = max(
            Constants.minThickness,
            ceil(CGFloat(digitCount) * cachedDigitWidth + Constants.horizontalPadding * 2)
        )
        if abs(ruleThickness - requiredThickness) > 0.5 {
            ruleThickness = requiredThickness
            onRuleThicknessChanged?(requiredThickness)
        }
    }

    private func handleThemeDidChange() {
        applyTheme()
        cachedSelectedAttributes = nil
        cachedUnselectedAttributes = nil
        needsDisplay = true
    }

    private func applyTheme() {
        layer?.backgroundColor = AppColors.editorBackground.cgColor
    }

    func handleSelectionDidChange() {
        let nextSelectedLineStart = selectedLineStart()
        guard nextSelectedLineStart != lastSelectedLineStart else {
            return
        }

        lastSelectedLineStart = nextSelectedLineStart
        needsDisplay = true
    }

    private func lineNumberAttributes(isSelected: Bool) -> [NSAttributedString.Key: Any] {
        if isSelected, let cachedSelectedAttributes {
            return cachedSelectedAttributes
        }

        if !isSelected, let cachedUnselectedAttributes {
            return cachedUnselectedAttributes
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont(),
            .foregroundColor: isSelected ? AppColors.sidebarHeaderText : AppColors.lineNumberText,
            .paragraphStyle: paragraphStyle,
        ]

        if isSelected {
            cachedSelectedAttributes = attributes
        } else {
            cachedUnselectedAttributes = attributes
        }

        return attributes
    }
}
