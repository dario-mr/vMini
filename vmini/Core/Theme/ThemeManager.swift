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
    private let observers = Observers<State>()

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
        observers.add(observer, initialState: currentState())
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
        observers.notify(currentState())
    }
}
