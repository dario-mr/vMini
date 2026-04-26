import AppKit

enum EditorSettings {
    private enum Constants {
        static let defaultFontSize: CGFloat = 13
        static let minFontSize: CGFloat = 8
        static let maxFontSize: CGFloat = 32
    }

    static let didChangeNotification = Notification.Name("EditorFontSizeDidChange")
    static let wordWrapDidChangeNotification = Notification.Name("EditorWordWrapDidChange")

    static func currentFontSize() -> CGFloat {
        let storedFontSize = UserDefaults.standard.double(forKey: UserDefaultsKeys.editorFontSize)
        guard storedFontSize > 0 else {
            return Constants.defaultFontSize
        }

        return clampedFontSize(CGFloat(storedFontSize))
    }

    static func increaseFontSize() {
        setFontSize(currentFontSize() + 1)
    }

    static func decreaseFontSize() {
        setFontSize(currentFontSize() - 1)
    }

    static func isWordWrapEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.editorWordWrapEnabled)
    }

    static func toggleWordWrap() {
        setWordWrapEnabled(!isWordWrapEnabled())
    }

    static func setFontSize(_ fontSize: CGFloat) {
        let clampedFontSize = clampedFontSize(fontSize)
        guard clampedFontSize != currentFontSize() else {
            return
        }

        UserDefaults.standard.set(Double(clampedFontSize), forKey: UserDefaultsKeys.editorFontSize)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func setWordWrapEnabled(_ isEnabled: Bool) {
        guard isEnabled != isWordWrapEnabled() else {
            return
        }

        UserDefaults.standard.set(isEnabled, forKey: UserDefaultsKeys.editorWordWrapEnabled)
        NotificationCenter.default.post(name: wordWrapDidChangeNotification, object: nil)
    }

    private static func clampedFontSize(_ fontSize: CGFloat) -> CGFloat {
        min(max(fontSize, Constants.minFontSize), Constants.maxFontSize)
    }
}
