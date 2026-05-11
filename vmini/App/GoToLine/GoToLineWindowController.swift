import AppKit

private final class GoToLineSheetWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }
}

@MainActor
final class GoToLineWindowController: NSWindowController, NSWindowDelegate {
    private let goToLineViewController = GoToLineViewController()

    init() {
        let contentSize = goToLineViewController.preferredContentSize
        let window = GoToLineSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = goToLineViewController
        window.title = "Go to Line"
        window.isReleasedWhenClosed = false
        window.delegate = nil

        super.init(window: window)
        self.window?.delegate = self

        goToLineViewController.onCancel = { [weak self] in
            self?.closeSheet()
        }
        window.onCancel = { [weak self] in
            self?.closeSheet()
        }

        applyTheme()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func present(
        currentLineNumber: Int,
        asSheetFor hostWindow: NSWindow,
        onGoToLine: @escaping (Int) -> Void
    ) {
        guard let window else { return }
        guard window.sheetParent == nil else { return }

        goToLineViewController.configure(currentLineNumber: currentLineNumber)
        goToLineViewController.onGoToLine = { [weak self] lineNumber in
            onGoToLine(lineNumber)
            self?.closeSheet()
        }

        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.setContentSize(goToLineViewController.preferredContentSize)
        hostWindow.beginSheet(window)

        DispatchQueue.main.async { [weak self] in
            self?.goToLineViewController.focusLineNumberField()
        }
    }

    func closeSheet() {
        guard let window, let parentWindow = window.sheetParent else { return }
        parentWindow.endSheet(window)
    }

    func windowWillClose(_ notification: Notification) {
        closeSheet()
    }

    private func applyTheme() {
        window?.backgroundColor = AppColors.windowBackground
    }

    @objc
    private func handleThemeDidChange() {
        applyTheme()
    }
}
