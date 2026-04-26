import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
let documentController = DocumentController()

app.setActivationPolicy(.regular)
app.delegate = delegate

// Ensure the shared document controller is initialized before the app starts dispatching actions.
_ = documentController

app.run()
