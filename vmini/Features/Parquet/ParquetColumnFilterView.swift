import AppKit

final class ParquetColumnFilterView: NSView, NSTextFieldDelegate {
    let column: ParquetPage.Column
    var onChange: ((ParquetQuery.Filter?, Bool) -> Void)?
    private let kind: ParquetColumnKind
    private let operators = NSPopUpButton(frame: .zero, pullsDown: false)
    private let value = FilterField()

    init(column: ParquetPage.Column, filter: ParquetQuery.Filter?) {
        self.column = column
        kind = ParquetColumnKind(type: column.type)
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: ParquetTableStyle.Layout.filterControlHeight))
        operators.addItems(withTitles: kind.operators.map { kind.title(for: $0) })
        operators.controlSize = .small
        operators.font = .systemFont(ofSize: ParquetTableStyle.Layout.controlFontSize)
        operators.setAccessibilityLabel("Filter operator for \(column.name)")
        operators.frame = bounds
        operators.autoresizingMask = [.width]
        operators.target = self
        operators.action = #selector(operatorChanged)
        addSubview(operators)
        if kind != .boolean && kind != .other {
            let width: CGFloat = kind == .text ? 85 : kind == .date ? 75 : 55
            operators.frame.size.width = width
            operators.autoresizingMask = []
            value.font = .systemFont(ofSize: ParquetTableStyle.Layout.controlFontSize)
            value.bezelStyle = .roundedBezel
            value.focusRingType = .none
            value.setAccessibilityLabel("Filter value for \(column.name)")
            let height = value.intrinsicContentSize.height
            value.frame = NSRect(x: width + 4, y: ((ParquetTableStyle.Layout.filterControlHeight - height) / 2).rounded(), width: 150 - width - 4, height: height)
            value.autoresizingMask = [.width]
            value.delegate = self
            addSubview(value)
        }
        reset(filter: filter)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reset(filter: ParquetQuery.Filter?) {
        let operation = filter?.operation ?? kind.operators[0]
        operators.selectItem(at: kind.operators.firstIndex(of: operation) ?? 0)
        value.stringValue = filter?.value ?? ""
        value.isEnabled = operation.needsValue
    }

    @objc private func operatorChanged() {
        value.isEnabled = operation.needsValue
        sendChange(debounce: false)
    }

    func controlTextDidChange(_ notification: Notification) { sendChange(debounce: true) }

    private var operation: ParquetQuery.Operator { kind.operators[max(0, operators.indexOfSelectedItem)] }

    private func sendChange(debounce: Bool) {
        let text = kind == .text ? value.stringValue : value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let inactive = operation == .any || (operation.needsValue && text.isEmpty && !(kind == .text && operation == .equals))
        onChange?(inactive ? nil : ParquetQuery.Filter(operation: operation, value: text), debounce)
    }
}

private final class FilterField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { showsFocus = true }
        return became
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        showsFocus = false
    }

    private var showsFocus = false {
        didSet {
            wantsLayer = true
            layer?.cornerRadius = 5
            layer?.borderWidth = showsFocus ? 1 : 0
            layer?.borderColor = ParquetTableStyle.focusBorder.cgColor
        }
    }
}
