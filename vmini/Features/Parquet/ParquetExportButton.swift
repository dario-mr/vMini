import AppKit

/// Export CSV button that fills with progress while exporting and offers Cancel on hover.
final class ParquetExportButton: AppButton {
    private static let idleTitle = "Export CSV"
    private let progressLayer = CALayer()
    private var idleWidth: CGFloat = 0
    private var isHovered = false
    private var themeObservation: ObservationToken?
    private(set) var isExporting = false
    private var fraction: Double?

    init() {
        super.init(title: Self.idleTitle, style: .secondary)
        idleWidth = super.intrinsicContentSize.width
        layer?.masksToBounds = true
        progressLayer.isHidden = true
        layer?.insertSublayer(progressLayer, at: 0)
        themeObservation = ThemeManager.shared.observe { [weak self] _ in self?.applyProgressColor() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(size.width, idleWidth), height: size.height)
    }

    func setExporting(_ isExporting: Bool) {
        self.isExporting = isExporting
        fraction = nil
        progressLayer.isHidden = !isExporting
        updateProgress(animated: false)
    }

    func setProgress(_ fraction: Double?) {
        guard isExporting else { return }
        self.fraction = fraction
        updateProgress(animated: true)
    }

    override func layout() {
        super.layout()
        updateProgress(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateTitle()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateTitle()
    }

    private func updateProgress(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        progressLayer.frame = NSRect(x: 0, y: 0, width: bounds.width * (fraction ?? 0), height: bounds.height)
        CATransaction.commit()
        applyProgressColor()
        updateTitle()
    }

    private func updateTitle() {
        let percent = "\(Int((fraction ?? 0) * 100))%"
        let title = !isExporting ? Self.idleTitle : isHovered ? "Cancel" : percent
        if self.title != title { self.title = title }
    }

    private func applyProgressColor() {
        progressLayer.backgroundColor = AppColors.primaryActionBackground.withAlphaComponent(0.35).cgColor
    }
}
