import AppKit

final class LineNumberRulerView: NSView {
    private enum Constants {
        static let minThickness: CGFloat = 36
        static let horizontalPadding: CGFloat = 8
    }

    private weak var textView: NSTextView?
    var onRuleThicknessChanged: ((CGFloat) -> Void)?
    private(set) var ruleThickness = Constants.minThickness
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
        layer?.backgroundColor = AppColors.editorBackground.cgColor
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
        let requiredThickness = requiredThickness()
        if abs(ruleThickness - requiredThickness) > 0.5 {
            ruleThickness = requiredThickness
            onRuleThicknessChanged?(requiredThickness)
        }
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
        guard let text = textView?.string, characterIndex > 0 else {
            return 1
        }

        let prefix = (text as NSString).substring(to: min(characterIndex, (text as NSString).length))
        return prefix.reduce(1) { lineNumber, character in
            character == "\n" ? lineNumber + 1 : lineNumber
        }
    }

    private func requiredThickness() -> CGFloat {
        guard let text = textView?.string else {
            return Constants.minThickness
        }

        let lineCount = max(1, text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
        let digitCount = "\(lineCount)".count
        let digitWidth = "0".size(withAttributes: [
            .font: lineNumberFont(),
        ]).width
        return max(Constants.minThickness, ceil(CGFloat(digitCount) * digitWidth + Constants.horizontalPadding * 2))
    }
}
