import Foundation

@MainActor
final class SyntaxOverrideStore {
    static let shared = SyntaxOverrideStore()

    private let persistence: WorkspacePersistence

    init(persistence: WorkspacePersistence) {
        self.persistence = persistence
    }

    convenience init(userDefaults: UserDefaults) {
        self.init(persistence: WorkspacePersistence(userDefaults: userDefaults))
    }

    private convenience init() {
        self.init(persistence: .shared)
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
        persistence.syntaxLanguageOverrides = overrides
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
        persistence.syntaxLanguageOverrides
    }
}
