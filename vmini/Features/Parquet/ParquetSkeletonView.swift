import AppKit

/// Row backgrounds stay opaque so stale rows never show through; only the bars pulse.
final class ParquetSkeletonView: NSView {
    weak var tableView: NSTableView?
    private let bars = PulsingBars()
    private let barShapes = CAShapeLayer()

    override var isFlipped: Bool { true }

    override var needsDisplay: Bool {
        willSet { if newValue { updateBars() } }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.busyIndicator)
        setAccessibilityLabel("Updating Parquet rows")
        bars.wantsLayer = true
        bars.frame = bounds
        bars.autoresizingMask = [.width, .height]
        bars.layer?.addSublayer(barShapes)
        addSubview(bars)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setActive(_ active: Bool) {
        guard active == isHidden else { return }
        isHidden = !active
        bars.layer?.removeAnimation(forKey: "pulse")
        guard active else { return }
        needsDisplay = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.3
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bars.layer?.add(pulse, forKey: "pulse")
    }

    // Swallow clicks so stale rows underneath can't be selected mid-query.
    override func hitTest(_ point: NSPoint) -> NSView? { isHidden ? nil : (frame.contains(point) ? self : nil) }
    override func mouseDown(with event: NSEvent) {}

    override func layout() {
        super.layout()
        updateBars()
    }

    override func draw(_ dirtyRect: NSRect) {
        AppColors.editorBackground.setFill()
        bounds.fill()
        guard let rowHeight = tableView?.rowHeight else { return }
        for row in 0...Int(bounds.height / rowHeight) {
            let rowRect = NSRect(x: 0, y: CGFloat(row) * rowHeight, width: bounds.width, height: rowHeight)
            (row.isMultiple(of: 2) ? ParquetTableStyle.row : ParquetTableStyle.alternateRow).setFill()
            rowRect.fill()
            ParquetTableStyle.grid.setFill()
            NSRect(x: 0, y: rowRect.maxY - 1, width: bounds.width, height: 1).fill()
        }
        ParquetTableStyle.grid.setFill()
        forEachCell { _, _, rowRect, cell in
            NSRect(x: cell.maxX - 1, y: rowRect.minY, width: 1, height: rowRect.height).fill()
        }
    }

    private func updateBars() {
        let path = CGMutablePath()
        forEachCell { row, column, rowRect, cell in
            let fraction = column == 0 ? 0.5 : 0.35 + CGFloat((row * 7 + column * 13) % 5) * 0.12
            let inset = column == 0 ? ParquetTableStyle.Layout.rowNumberInset : ParquetTableStyle.Layout.cellInset
            let width = (cell.width - 2 * inset) * fraction
            let x = column == 0 ? cell.midX - width / 2 : cell.minX + inset
            let bar = NSRect(x: x, y: rowRect.midY - 5, width: width, height: 10)
            if bar.width >= 8 { path.addRoundedRect(in: bar, cornerWidth: 4, cornerHeight: 4) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barShapes.frame = bars.bounds
        barShapes.path = path
        barShapes.fillColor = AppColors.primaryText.withAlphaComponent(0.14).cgColor
        CATransaction.commit()
    }

    private func forEachCell(_ body: (_ row: Int, _ column: Int, _ rowRect: NSRect, _ cell: NSRect) -> Void) {
        guard let tableView else { return }
        let rowHeight = tableView.rowHeight
        for row in 0...Int(bounds.height / rowHeight) {
            let rowRect = NSRect(x: 0, y: CGFloat(row) * rowHeight, width: bounds.width, height: rowHeight)
            for column in tableView.tableColumns.indices {
                let cell = convert(tableView.rect(ofColumn: column), from: tableView)
                guard cell.maxX > 0, cell.minX < bounds.width else { continue }
                body(row, column, rowRect, cell)
            }
        }
    }

    private final class PulsingBars: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
