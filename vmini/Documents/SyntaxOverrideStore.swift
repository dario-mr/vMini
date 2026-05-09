import Foundation

@MainActor
final class SyntaxOverrideStore {
    static let shared = SyntaxOverrideStore()

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = UserDefaultsKeys.syntaxLanguageOverrides
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func override(for documentIdentifier: String) -> SyntaxLanguage? {
        guard let rawValue = storedOverrides()[documentIdentifier] else {
            return nil
        }

        return SyntaxLanguage(rawValue: rawValue)
    }

    func setOverride(_ language: SyntaxLanguage?, for documentIdentifier: String) {
        var overrides = storedOverrides()
        if let language {
            overrides[documentIdentifier] = language.rawValue
        } else {
            overrides.removeValue(forKey: documentIdentifier)
        }
        userDefaults.set(overrides, forKey: storageKey)
    }

    func removeOverride(for documentIdentifier: String) {
        setOverride(nil, for: documentIdentifier)
    }

    func migrateOverride(from oldIdentifier: String, to newIdentifier: String, currentOverride: SyntaxLanguage?) {
        guard oldIdentifier != newIdentifier else { return }

        let overrideToPersist = currentOverride ?? override(for: oldIdentifier)
        removeOverride(for: oldIdentifier)
        setOverride(overrideToPersist, for: newIdentifier)
    }

    private func storedOverrides() -> [String: String] {
        userDefaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }
}
