import Foundation

@MainActor
final class ThemeManager {
    struct State {
        let selectedThemeID: ThemeID
        let palette: ThemePalette
        let syntaxTheme: SyntaxTheme
    }

    static let shared = ThemeManager()

    private let store: ThemeStore
    private(set) var selectedThemeID: ThemeID
    private var observers: [UUID: (State) -> Void] = [:]

    private init(store: ThemeStore) {
        self.store = store
        self.selectedThemeID = store.currentThemeID()
    }

    private convenience init() {
        self.init(store: ThemeStore())
    }

    var palette: ThemePalette {
        ThemeCatalog.palette(for: selectedThemeID)
    }

    var syntaxTheme: SyntaxTheme {
        palette.syntaxTheme
    }

    func observe(_ observer: @escaping (State) -> Void) -> ObservationToken {
        let identifier = UUID()
        observers[identifier] = observer
        observer(currentState())
        return ObservationToken { [weak self] in
            self?.observers.removeValue(forKey: identifier)
        }
    }

    func setThemeID(_ themeID: ThemeID) {
        guard themeID != selectedThemeID else {
            return
        }

        selectedThemeID = themeID
        store.setThemeID(themeID)
        notifyObservers()
    }

    private func currentState() -> State {
        State(
            selectedThemeID: selectedThemeID,
            palette: palette,
            syntaxTheme: syntaxTheme
        )
    }

    private func notifyObservers() {
        let state = currentState()
        for observer in observers.values {
            observer(state)
        }
    }
}
