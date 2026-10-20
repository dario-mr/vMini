import AppKit

@main
@MainActor
enum VminiApp {
    static func main() {
        let app = NSApplication.shared
        // The delegate resolves workspace services that need our shared document controller.
        let documentController = DocumentController()
        assert(NSDocumentController.shared === documentController)
        let delegate = AppDelegate()

        app.setActivationPolicy(.regular)
        app.delegate = delegate

        // Ensure the shared document controller is initialized before the app starts dispatching actions.
        _ = documentController

        app.run()
    }
}
