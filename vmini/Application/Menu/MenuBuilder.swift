import AppKit

@MainActor
enum MenuBuilder {
    static func installMainMenu(commandTarget: AnyObject?) {
        let mainMenu = NSMenu(title: "Main Menu")
        let appMenuItem = NSMenuItem(title: ProcessInfo.processInfo.processName, action: nil, keyEquivalent: "")
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")

        mainMenu.removeAllItems()
        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(fileMenuItem)
        mainMenu.addItem(editMenuItem)
        mainMenu.addItem(viewMenuItem)
        mainMenu.addItem(windowMenuItem)

        mainMenu.setSubmenu(makeAppMenu(commandTarget: commandTarget), for: appMenuItem)
        mainMenu.setSubmenu(makeFileMenu(commandTarget: commandTarget), for: fileMenuItem)
        mainMenu.setSubmenu(makeEditMenu(commandTarget: commandTarget), for: editMenuItem)
        mainMenu.setSubmenu(makeViewMenu(commandTarget: commandTarget), for: viewMenuItem)
        mainMenu.setSubmenu(makeWindowMenu(), for: windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenuItem.submenu
    }

    private static func makeAppMenu(commandTarget: AnyObject?) -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: appName)

        menu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(AppCommandDispatcher.showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = commandTarget
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit \(appName)", action: #selector(AppDelegate.performQuit(_:)), keyEquivalent: "q")
        quitItem.target = NSApp.delegate as AnyObject?

        return menu
    }

    private static func makeFileMenu(commandTarget: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "File")

        let newItem = menu.addItem(withTitle: "New", action: #selector(AppCommandDispatcher.newDocument(_:)), keyEquivalent: "n")
        newItem.target = commandTarget
        let openItem = menu.addItem(withTitle: "Open…", action: #selector(AppCommandDispatcher.openDocumentOrFolder(_:)), keyEquivalent: "o")
        openItem.target = commandTarget
        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        openRecentItem.submenu = makeOpenRecentMenu(commandTarget: commandTarget)
        menu.addItem(openRecentItem)

        menu.addItem(.separator())
        let closeItem = menu.addItem(withTitle: "Close", action: #selector(AppCommandDispatcher.closeCurrentDocument(_:)), keyEquivalent: "w")
        closeItem.target = commandTarget
        let reopenClosedItem = menu.addItem(withTitle: "Reopen Closed Tab", action: #selector(AppCommandDispatcher.reopenClosedDocument(_:)), keyEquivalent: "T")
        reopenClosedItem.target = commandTarget
        let saveItem = menu.addItem(withTitle: "Save", action: #selector(AppCommandDispatcher.saveCurrentDocument(_:)), keyEquivalent: "s")
        saveItem.target = commandTarget
        let saveAsItem = menu.addItem(withTitle: "Save As…", action: #selector(AppCommandDispatcher.saveCurrentDocumentAs(_:)), keyEquivalent: "S")
        saveAsItem.target = commandTarget

        return menu
    }

    private static func makeOpenRecentMenu(commandTarget: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "Open Recent")
        let recentURLs = NSDocumentController.shared.recentDocumentURLs.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }

        if recentURLs.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        for url in recentURLs {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: #selector(AppCommandDispatcher.openRecentDocument(_:)),
                keyEquivalent: ""
            )
            item.target = commandTarget
            item.representedObject = url
            item.toolTip = (url.path as NSString).abbreviatingWithTildeInPath
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let clearItem = NSMenuItem(
            title: "Clear Menu",
            action: #selector(AppCommandDispatcher.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clearItem.target = commandTarget
        menu.addItem(clearItem)

        return menu
    }

    private static func makeEditMenu(commandTarget: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let goToLineItem = menu.addItem(withTitle: "Go to Line…", action: #selector(AppCommandDispatcher.showGoToLine(_:)), keyEquivalent: "l")
        goToLineItem.target = commandTarget
        let formatJSONItem = menu.addItem(withTitle: "Format JSON", action: #selector(AppCommandDispatcher.formatJSON(_:)), keyEquivalent: "j")
        formatJSONItem.target = commandTarget
        menu.addItem(.separator())

        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findMenuItem.submenu = makeFindMenu()
        menu.addItem(findMenuItem)

        return menu
    }

    private static func makeFindMenu() -> NSMenu {
        let menu = NSMenu(title: "Find")

        let showFind = menu.addItem(withTitle: "Find…", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
        showFind.tag = NSTextFinder.Action.showFindInterface.rawValue

        let findNext = menu.addItem(withTitle: "Find Next", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "g")
        findNext.tag = NSTextFinder.Action.nextMatch.rawValue

        let findPrevious = menu.addItem(withTitle: "Find Previous", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "G")
        findPrevious.tag = NSTextFinder.Action.previousMatch.rawValue

        return menu
    }

    private static func makeViewMenu(commandTarget: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "View")
        let wordWrapItem = menu.addItem(
            withTitle: "Word Wrap",
            action: #selector(AppCommandDispatcher.toggleWordWrap(_:)),
            keyEquivalent: ""
        )
        wordWrapItem.target = commandTarget
        wordWrapItem.state = EditorSettings.isWordWrapEnabled() ? .on : .off

        let invisibleCharactersItem = menu.addItem(
            withTitle: "Show Invisible Characters",
            action: #selector(AppCommandDispatcher.toggleInvisibleCharacters(_:)),
            keyEquivalent: ""
        )
        invisibleCharactersItem.target = commandTarget
        invisibleCharactersItem.state = EditorSettings.showsInvisibleCharacters() ? .on : .off

        return menu
    }

    private static func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")

        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        return menu
    }
}
