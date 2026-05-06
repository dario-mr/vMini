import Foundation

final class ThemeManager {
    static let didChangeNotification = Notification.Name("ThemeDidChange")
    nonisolated(unsafe) static let shared = ThemeManager()

    private let store: ThemeStore
    private(set) var selectedThemeID: ThemeID

    private init(store: ThemeStore = ThemeStore()) {
        self.store = store
        self.selectedThemeID = store.currentThemeID()
    }

    var palette: ThemePalette {
        ThemeCatalog.palette(for: selectedThemeID)
    }

    var syntaxTheme: SyntaxTheme {
        palette.syntaxTheme
    }

    func setThemeID(_ themeID: ThemeID) {
        guard themeID != selectedThemeID else {
            return
        }

        selectedThemeID = themeID
        store.setThemeID(themeID)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
