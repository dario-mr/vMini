import Foundation

struct ThemeStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func currentThemeID() -> ThemeID {
        guard
            let storedValue = userDefaults.string(forKey: UserDefaultsKeys.themeID),
            let themeID = ThemeID(rawValue: storedValue)
        else {
            return .default
        }

        return themeID
    }

    func setThemeID(_ themeID: ThemeID) {
        userDefaults.set(themeID.rawValue, forKey: UserDefaultsKeys.themeID)
    }
}
