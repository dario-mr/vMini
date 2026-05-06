import AppKit

@MainActor
final class SettingsCoordinator {
    static let shared = SettingsCoordinator()

    private lazy var settingsWindowController = SettingsWindowController()

    func presentSettingsSheet(attachedTo hostWindow: NSWindow) {
        settingsWindowController.present(asSheetFor: hostWindow)
    }
}
