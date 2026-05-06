import AppKit

private final class SettingsSheetWindow: NSWindow {
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
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsViewController = SettingsViewController()

    init() {
        let contentSize = settingsViewController.preferredContentSize
        let window = SettingsSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = settingsViewController
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.delegate = nil

        super.init(window: window)
        self.window?.delegate = self

        settingsViewController.onDone = { [weak self] in
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

    func present(asSheetFor hostWindow: NSWindow) {
        guard let window else { return }
        guard window.sheetParent == nil else { return }
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.setContentSize(settingsViewController.preferredContentSize)
        hostWindow.beginSheet(window)
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
