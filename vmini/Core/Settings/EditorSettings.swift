import AppKit

@MainActor
enum EditorSettings {
    struct State {
        let fontID: EditorFontID
        let fontSize: CGFloat
        let wordWrapEnabled: Bool
        let showsInvisibleCharacters: Bool
    }

    private enum Constants {
        static let defaultFontSize: CGFloat = 13
        static let fontSizeStep: CGFloat = 0.5
        static let minFontSize: CGFloat = 8
        static let maxFontSize: CGFloat = 32
    }

    static var userDefaults: UserDefaults = .standard
    private static var observers: [UUID: (State) -> Void] = [:]

    static func observe(_ observer: @escaping (State) -> Void) -> ObservationToken {
        let identifier = UUID()
        observers[identifier] = observer
        observer(currentState())
        return ObservationToken {
            observers.removeValue(forKey: identifier)
        }
    }

    static func currentFontID() -> EditorFontID {
        guard
            let storedValue = userDefaults.string(forKey: UserDefaultsKeys.editorFontID),
            let fontID = EditorFontID(rawValue: storedValue),
            EditorFontResolver.isAvailable(fontID)
        else {
            return .fallback
        }

        return fontID
    }

    static func currentFontSize() -> CGFloat {
        let storedFontSize = userDefaults.double(forKey: UserDefaultsKeys.editorFontSize)
        guard storedFontSize > 0 else {
            return Constants.defaultFontSize
        }

        return clampedFontSize(CGFloat(storedFontSize))
    }

    static func increaseFontSize() {
        setFontSize(currentFontSize() + Constants.fontSizeStep)
    }

    static func decreaseFontSize() {
        setFontSize(currentFontSize() - Constants.fontSizeStep)
    }

    static func isWordWrapEnabled() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKeys.editorWordWrapEnabled)
    }

    static func toggleWordWrap() {
        setWordWrapEnabled(!isWordWrapEnabled())
    }

    static func showsInvisibleCharacters() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKeys.editorShowsInvisibleCharacters)
    }

    static func toggleInvisibleCharacters() {
        setShowsInvisibleCharacters(!showsInvisibleCharacters())
    }

    static func setFontID(_ fontID: EditorFontID) {
        guard fontID != currentFontID() else {
            return
        }

        userDefaults.set(fontID.rawValue, forKey: UserDefaultsKeys.editorFontID)
        notifyObservers()
    }

    static func setFontSize(_ fontSize: CGFloat) {
        let clampedFontSize = clampedFontSize(fontSize)
        guard clampedFontSize != currentFontSize() else {
            return
        }

        userDefaults.set(Double(clampedFontSize), forKey: UserDefaultsKeys.editorFontSize)
        notifyObservers()
    }

    static func setWordWrapEnabled(_ isEnabled: Bool) {
        guard isEnabled != isWordWrapEnabled() else {
            return
        }

        userDefaults.set(isEnabled, forKey: UserDefaultsKeys.editorWordWrapEnabled)
        notifyObservers()
    }

    static func setShowsInvisibleCharacters(_ isEnabled: Bool) {
        guard isEnabled != showsInvisibleCharacters() else {
            return
        }

        userDefaults.set(isEnabled, forKey: UserDefaultsKeys.editorShowsInvisibleCharacters)
        notifyObservers()
    }

    private static func clampedFontSize(_ fontSize: CGFloat) -> CGFloat {
        min(max(fontSize, Constants.minFontSize), Constants.maxFontSize)
    }

    private static func currentState() -> State {
        State(
            fontID: currentFontID(),
            fontSize: currentFontSize(),
            wordWrapEnabled: isWordWrapEnabled(),
            showsInvisibleCharacters: showsInvisibleCharacters()
        )
    }

    private static func notifyObservers() {
        let state = currentState()
        for observer in observers.values {
            observer(state)
        }
    }
}
